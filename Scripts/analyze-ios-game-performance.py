#!/usr/bin/env python3
"""Export-free post-processing for an already-recorded Dark Eco xctrace capture.

This tool never records or enumerates devices.  It only reads XML exports that
`xcrun xctrace export` created from an existing trace.  `--export-missing` is
also read-only: it calls `xctrace export`, never `xctrace record`.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import subprocess
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any


PROCESS_NAME = "Dark Eco"
KNOWN_SCHEMAS = {
    "metal-perf-overview-layer-per-frame-metric",
    "metal-perf-overview-layer-per-frame-interval-metric",
    "metal-perf-overview-layer-duration-metric",
    "time-profile",
    "device-thermal-state-intervals",
}
FRAME_SCHEMAS = (
    "metal-perf-overview-layer-per-frame-metric",
    "metal-perf-overview-layer-duration-metric",
)
INTERVAL_SCHEMA = "metal-perf-overview-layer-per-frame-interval-metric"
CPU_SCHEMA = "time-profile"
THERMAL_SCHEMA = "device-thermal-state-intervals"
CADENCE_HZ = (120, 80, 60, 48, 40, 30, 24)
CATALOG_VALUE_COLUMNS = {
    "metal-perf-overview-layer-per-frame-metric": "metric-value",
    "metal-perf-overview-layer-per-frame-interval-metric": "duration",
    "metal-perf-overview-layer-duration-metric": "value-in-ms",
}


class AnalysisError(RuntimeError):
    pass


@dataclass(frozen=True)
class Cell:
    raw: str | None
    display: str | None
    tag: str


def display_value(element: ET.Element | None) -> str | None:
    if element is None:
        return None
    return element.attrib.get("fmt") or (element.text or "").strip() or None


def raw_value(element: ET.Element | None) -> str | None:
    if element is None:
        return None
    return (element.text or "").strip() or None


def parse_number(value: str | None) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except ValueError:
        return None


def row_display(row: dict[str, Cell], column: str) -> str | None:
    value = row.get(column)
    return value.display if value is not None else None


def duration_ms(value: Cell | None, context: str) -> float:
    if value is None or value.tag != "duration":
        tag = value.tag if value is not None else None
        raise AnalysisError(f"{context} requires a duration-tag value in nanoseconds, got {tag}")
    raw = parse_number(value.raw)
    if raw is None or raw < 0:
        raise AnalysisError(f"{context} has an invalid duration payload")
    return raw / 1_000_000.0


def value_in_ms(value: Cell | None, context: str) -> float:
    if value is None:
        raise AnalysisError(f"{context} is missing")
    raw = parse_number(value.raw)
    if raw is None:
        raise AnalysisError(f"{context} has an invalid millisecond payload")
    return raw


def frame_metric_ms(row: dict[str, Cell], requested: str) -> float:
    duration = row.get("metric-value")
    if duration is not None:
        if duration.tag != "duration":
            raise AnalysisError(
                f"named metric {requested} has unsupported metric-value unit/tag "
                f"{duration.tag}; only duration-tag metric values are normalized to ms"
            )
        return duration_ms(duration, f"named metric {requested}")
    return value_in_ms(row.get("value-in-ms"), f"named metric {requested}")


def percentile(values: list[float], fraction: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * fraction) - 1)]


def metric_summary(values: list[float]) -> dict[str, Any]:
    return {
        "sample_count": len(values),
        "mean_ms": round(sum(values) / len(values), 6) if values else None,
        "p50_ms": round(percentile(values, 0.50), 6) if values else None,
        "p95_ms": round(percentile(values, 0.95), 6) if values else None,
        "p99_ms": round(percentile(values, 0.99), 6) if values else None,
        "max_ms": round(max(values), 6) if values else None,
    }


def read_metadata(path: Path | None) -> dict[str, str]:
    if path is None or not path.is_file():
        return {}
    result: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            result[key] = value
    return result


def find_one(directory: Path, pattern: str) -> Path | None:
    matches = sorted(directory.glob(pattern))
    if len(matches) > 1:
        raise AnalysisError(f"ambiguous {pattern} under {directory}")
    return matches[0] if matches else None


def discover_input(path: Path) -> tuple[Path | None, Path | None, Path | None]:
    if path.is_dir() and path.suffix == ".trace":
        return path, None, None
    if path.is_file() and path.suffix == ".trace":
        return path, None, None
    if not path.is_dir():
        raise AnalysisError(f"input is neither a capture directory nor a .trace: {path}")
    return find_one(path, "*.trace"), find_one(path, "*-toc.xml"), find_one(path, "*-metadata.txt")


def export_xml(trace: Path, schema: str | None, output: Path) -> None:
    command = ["xcrun", "xctrace", "export", "--input", str(trace)]
    if schema is None:
        command.extend(["--toc", "--output", str(output)])
    else:
        xpath = f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]'
        command.extend(["--xpath", xpath, "--output", str(output)])
    try:
        subprocess.run(command, check=True, capture_output=True, text=True)
    except FileNotFoundError as error:
        raise AnalysisError("xcrun is unavailable; provide exported XML instead") from error
    except subprocess.CalledProcessError as error:
        detail = error.stderr.strip() or error.stdout.strip() or str(error)
        raise AnalysisError(f"xctrace export failed: {detail}") from error


def toc_schemas(toc: Path) -> tuple[dict[str, Any], list[str]]:
    try:
        root = ET.parse(toc).getroot()
    except ET.ParseError as error:
        raise AnalysisError(f"invalid TOC XML: {toc}: {error}") from error
    run = root.find("./run")
    if run is None:
        raise AnalysisError("TOC has no run")
    summary = run.find("./info/summary")
    provenance = {
        "trace_run": run.attrib.get("number"),
        "template": display_value(summary.find("template-name") if summary is not None else None),
        "xctrace_version": display_value(summary.find("instruments-version") if summary is not None else None),
        "duration_seconds": parse_number(raw_value(summary.find("duration") if summary is not None else None)),
    }
    schemas = [table.attrib["schema"] for table in run.findall("./data/table[@schema]")]
    return provenance, sorted(set(schemas))


def element_index(root: ET.Element) -> dict[str, ET.Element]:
    return {element.attrib["id"]: element for element in root.iter() if "id" in element.attrib}


def resolved_cell(element: ET.Element, indexed: dict[str, ET.Element], seen: set[str] | None = None) -> Cell:
    reference = element.attrib.get("ref")
    if reference is not None:
        seen = set() if seen is None else seen
        if reference in seen:
            raise AnalysisError(f"cyclic XML reference: {reference}")
        if reference not in indexed:
            raise AnalysisError(f"unresolved XML reference: {reference}")
        seen.add(reference)
        return resolved_cell(indexed[reference], indexed, seen)
    raw = (element.text or "").strip() or None
    return Cell(raw=raw, display=element.attrib.get("fmt") or raw, tag=element.tag)


def query_rows(path: Path, expected_schema: str) -> list[dict[str, Cell]]:
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as error:
        raise AnalysisError(f"invalid exported XML: {path}: {error}") from error
    schema = root.find(".//schema")
    if schema is None or schema.attrib.get("name") != expected_schema:
        actual = schema.attrib.get("name") if schema is not None else None
        raise AnalysisError(f"schema mismatch for {path}: expected {expected_schema}, got {actual}")
    columns = [display_value(column.find("mnemonic")) for column in schema.findall("col")]
    if not columns or any(column is None for column in columns):
        raise AnalysisError(f"schema {expected_schema} has unusable columns")
    indexed = element_index(root)
    rows: list[dict[str, Cell]] = []
    for row in root.findall(".//row"):
        values = list(row)
        if len(values) != len(columns):
            raise AnalysisError(f"schema {expected_schema} row has {len(values)} values, expected {len(columns)}")
        rows.append({columns[index]: resolved_cell(value, indexed) for index, value in enumerate(values)})
    return rows


def is_dark_eco(row: dict[str, Cell]) -> bool:
    name = row_display(row, "process-name")
    if name is not None:
        return name == PROCESS_NAME
    process = row_display(row, "process")
    return process == PROCESS_NAME or (process is not None and process.startswith(f"{PROCESS_NAME} ("))


def named_metric(rows: list[dict[str, Cell]], requested: str | None) -> dict[str, Any]:
    if requested is None:
        return {"available": False, "reason": "no explicit metric name or label was requested"}
    matching = [row for row in rows if is_dark_eco(row) and requested in (row_display(row, "name"), row_display(row, "label"))]
    pairs = {(row_display(row, "name"), row_display(row, "label")) for row in matching}
    if not matching:
        return {"available": False, "reason": f"named metric not present for {PROCESS_NAME}: {requested}"}
    if len(pairs) != 1:
        return {"available": False, "reason": f"named metric is ambiguous: {requested}", "candidates": sorted(pairs, key=lambda pair: (pair[0] or "", pair[1] or ""))}
    values: list[float] = []
    for row in matching:
        values.append(frame_metric_ms(row, requested))
    name, label = next(iter(pairs))
    return {"available": True, "name": name, "label": label, **metric_summary(values)}


def classify_cadence(interval_ms: float) -> str:
    closest = min(CADENCE_HZ, key=lambda hz: abs(interval_ms - 1000.0 / hz))
    ideal = 1000.0 / closest
    return str(closest) if abs(interval_ms - ideal) <= ideal * 0.08 else "unclassified"


def cadence_runs(classifications: list[str]) -> list[dict[str, Any]]:
    runs: list[dict[str, Any]] = []
    for classification in classifications:
        if runs and runs[-1]["classification"] == classification:
            runs[-1]["sample_count"] += 1
        else:
            runs.append({"classification": classification, "sample_count": 1})
    return runs


def metric_catalog(schema_rows: dict[str, list[dict[str, Cell]]]) -> list[dict[str, Any]]:
    catalog: list[dict[str, Any]] = []
    for schema in sorted(CATALOG_VALUE_COLUMNS):
        value_column = CATALOG_VALUE_COLUMNS[schema]
        groups: dict[tuple[str | None, str | None], list[Cell]] = {}
        for row in schema_rows.get(schema, []):
            if is_dark_eco(row):
                value = row.get(value_column)
                if value is None:
                    raise AnalysisError(f"schema {schema} is missing its expected {value_column} column")
                groups.setdefault((row_display(row, "name"), row_display(row, "label")), []).append(value)
        for (name, label), values in sorted(groups.items(), key=lambda item: ((item[0][0] or ""), (item[0][1] or ""))):
            catalog.append({
                "schema": schema,
                "name": name,
                "label": label,
                "sample_count": len(values),
                "value_column": value_column,
                "observed_cell_tags": sorted({value.tag for value in values}),
                "display_examples": sorted({value.display for value in values if value.display is not None})[:3],
            })
    return catalog


def cadence(rows: list[dict[str, Cell]], selected: str | None, hitch_hz: int | None) -> dict[str, Any]:
    if selected is None:
        return {"available": False, "reason": "no explicit presentation metric name or label was requested"}
    matching = [row for row in rows if is_dark_eco(row) and selected in (row_display(row, "name"), row_display(row, "label"))]
    pairs = {(row_display(row, "name"), row_display(row, "label")) for row in matching}
    if not matching:
        return {"available": False, "reason": f"presentation metric not present for {PROCESS_NAME}: {selected}"}
    if len(pairs) != 1:
        return {"available": False, "reason": f"presentation metric is ambiguous: {selected}", "candidates": sorted(pairs, key=lambda pair: (pair[0] or "", pair[1] or ""))}
    intervals: list[float] = []
    for row in matching:
        interval = duration_ms(row.get("duration"), f"presentation metric {selected}")
        if interval <= 0:
            raise AnalysisError(f"presentation metric {selected} has an invalid duration")
        intervals.append(interval)
    classifications = [classify_cadence(interval) for interval in intervals]
    clusters: Counter[str] = Counter(classifications)
    result: dict[str, Any] = {"available": True, "name": next(iter(pairs))[0], "label": next(iter(pairs))[1], **metric_summary(intervals), "cadence_clusters": {str(hz): clusters[str(hz)] for hz in CADENCE_HZ}, "unclassified": clusters["unclassified"], "cadence_runs": cadence_runs(classifications)}
    if hitch_hz is None:
        result["multi_interval_hitch_candidates"] = {"available": False, "reason": "no hitch reference cadence was requested", "candidate_only": True, "note": "Candidates include legitimate adaptive cadence transitions; correlate cadence runs and trace events before calling a hitch."}
    else:
        if hitch_hz not in CADENCE_HZ:
            raise AnalysisError("--hitch-reference-hz must be one of 120, 80, 60, 48, 40, 30, 24")
        reference_ms = 1000.0 / hitch_hz
        result["multi_interval_hitch_candidates"] = {
            "available": True,
            "candidate_only": True,
            "note": "Candidates include legitimate adaptive cadence transitions; correlate cadence runs and trace events before calling a hitch.",
            "reference_hz": hitch_hz,
            "count": sum(interval >= reference_ms * 1.5 for interval in intervals),
            "threshold_ms": round(reference_ms * 1.5, 6),
        }
    return result


def thermal(rows: list[dict[str, Cell]]) -> dict[str, Any]:
    intervals = []
    for row in rows:
        start = row.get("start")
        if start is None or start.tag not in ("start-time", "event-time"):
            tag = start.tag if start is not None else None
            raise AnalysisError(f"thermal interval requires a time-tag start payload, got {tag}")
        start_ns = parse_number(start.raw)
        if start_ns is None:
            raise AnalysisError("thermal interval has invalid start payload")
        intervals.append({"start_ns": int(start_ns), "duration_ms": round(duration_ms(row.get("duration"), "thermal interval"), 6), "state": row_display(row, "thermal-state")})
    return {"available": True, "intervals": intervals}


def sampled_cpu(rows: list[dict[str, Cell]], trace_duration_seconds: float | None) -> dict[str, Any]:
    dark_rows = [row for row in rows if is_dark_eco(row)]
    if not dark_rows:
        return {"available": False, "reason": "no Dark Eco Time Profiler samples"}
    running = [row for row in dark_rows if row_display(row, "thread-state") == "Running"]
    weights: list[float] = []
    for row in running:
        weight = row.get("weight")
        if weight is None or weight.tag != "weight":
            tag = weight.tag if weight is not None else None
            return {"available": False, "reason": f"unsupported Time Profiler weight tag: {tag}"}
        value = parse_number(weight.raw)
        if value is None or value < 0:
            return {"available": False, "reason": "invalid Time Profiler weight payload"}
        weights.append(value)
    running_ns = sum(weights)
    stack_weights: Counter[str] = Counter()
    for row, weight in zip(running, weights):
        stack_weights[row_display(row, "stack") or "<no stack>"] += int(weight)
    occupancy = None
    if trace_duration_seconds and trace_duration_seconds > 0:
        occupancy = round(100.0 * running_ns / (trace_duration_seconds * 1_000_000_000.0), 6)
    return {
        "available": True,
        "measurement": "sampled Time Profiler running weight (raw nanoseconds); not exact CPU frame time",
        "sample_count": len(dark_rows),
        "running_sample_count": len(running),
        "running_weight_ms": round(running_ns / 1_000_000.0, 6),
        "running_occupancy_percent_of_capture": occupancy,
        "top_stacks": [{"stack": stack, "running_weight_ms": round(weight / 1_000_000.0, 6)} for stack, weight in sorted(stack_weights.items(), key=lambda item: (-item[1], item[0]))[:10]],
    }


def compact_rows(report: dict[str, Any]) -> list[dict[str, Any]]:
    rows = []
    for category in ("cadence", "cpu_frame_metric", "gpu_frame_metric"):
        value = report["measurements"][category]
        rows.append({"category": category, "available": value["available"], "name": value.get("name"), "label": value.get("label"), "sample_count": value.get("sample_count"), "mean_ms": value.get("mean_ms"), "p95_ms": value.get("p95_ms"), "max_ms": value.get("max_ms"), "detail": value.get("reason")})
    cpu = report["measurements"]["sampled_cpu"]
    rows.append({"category": "sampled_cpu", "available": cpu["available"], "name": None, "label": None, "sample_count": cpu.get("running_sample_count"), "mean_ms": None, "p95_ms": None, "max_ms": None, "detail": cpu.get("measurement") or cpu.get("reason")})
    rows.append({"category": "thermal", "available": report["measurements"]["thermal"]["available"], "name": None, "label": None, "sample_count": len(report["measurements"]["thermal"].get("intervals", [])), "mean_ms": None, "p95_ms": None, "max_ms": None, "detail": report["measurements"]["thermal"].get("reason")})
    return rows


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="capture directory or existing .trace")
    parser.add_argument("--output", required=True, type=Path, help="new analysis output directory")
    parser.add_argument("--toc", type=Path, help="explicit exported TOC XML")
    parser.add_argument("--xml", action="append", default=[], metavar="SCHEMA=PATH", help="explicit exported schema XML; repeatable")
    parser.add_argument("--export-missing", action="store_true", help="read-only xctrace export from the existing trace")
    parser.add_argument("--presentation-metric", help="exact observed presentation metric name or label")
    parser.add_argument("--cpu-metric", help="exact observed CPU frame metric name or label")
    parser.add_argument("--gpu-metric", help="exact observed GPU frame metric name or label")
    parser.add_argument("--hitch-reference-hz", type=int, help="explicit cadence used for candidate multi-interval hitches")
    args = parser.parse_args(argv)
    if args.output.exists():
        raise AnalysisError(f"output already exists: {args.output}")

    trace, found_toc, metadata_path = discover_input(args.input)
    toc = args.toc or found_toc
    supplied: dict[str, Path] = {}
    for specification in args.xml:
        if "=" not in specification:
            raise AnalysisError("--xml must be SCHEMA=PATH")
        schema, raw_path = specification.split("=", 1)
        if schema not in KNOWN_SCHEMAS:
            raise AnalysisError(f"unknown schema requested: {schema}")
        supplied[schema] = Path(raw_path)
    if toc is None:
        if not args.export_missing or trace is None:
            raise AnalysisError("missing TOC XML; provide it or use --export-missing with an existing trace")
        args.output.mkdir(parents=True)
        toc = args.output / "toc.xml"
        export_xml(trace, None, toc)
    provenance, inventory = toc_schemas(toc)
    unknown = sorted(set(inventory) - KNOWN_SCHEMAS)
    if not args.output.exists():
        args.output.mkdir(parents=True)
    toc_copy = args.output / "toc.xml"
    if toc.resolve() != toc_copy.resolve():
        toc_copy.write_bytes(toc.read_bytes())
    raw_directory = args.output / "raw"
    raw_directory.mkdir()
    schema_rows: dict[str, list[dict[str, Cell]]] = {}
    statuses: dict[str, dict[str, Any]] = {}
    for schema in sorted(KNOWN_SCHEMAS):
        source = supplied.get(schema)
        if source is None and args.input.is_dir():
            source = args.input / f"{schema}.xml"
            if not source.is_file():
                source = None
        if source is None and schema in inventory and args.export_missing:
            if trace is None:
                raise AnalysisError(f"cannot export {schema} without an existing trace")
            source = raw_directory / f"{schema}.xml"
            export_xml(trace, schema, source)
        if source is None:
            statuses[schema] = {"available": False, "reason": "missing exported schema XML"}
            continue
        if not source.is_file():
            raise AnalysisError(f"missing XML file for {schema}: {source}")
        raw_copy = raw_directory / f"{schema}.xml"
        if source.resolve() != raw_copy.resolve():
            raw_copy.write_bytes(source.read_bytes())
        schema_rows[schema] = query_rows(source, schema)
        statuses[schema] = {"available": True, "row_count": len(schema_rows[schema])}

    frame_rows = [row for schema in FRAME_SCHEMAS for row in schema_rows.get(schema, [])]
    report = {
        "schema_version": 1,
        "provenance": {"trace": str(trace) if trace else None, "toc": str(toc), **provenance, "capture_metadata": read_metadata(metadata_path)},
        "schema_inventory": {"known": [schema for schema in inventory if schema in KNOWN_SCHEMAS], "unknown_preserved_but_not_interpreted": unknown, "status": statuses},
        "process_filter": PROCESS_NAME,
        "metric_catalog": metric_catalog(schema_rows),
        "measurements": {
            "cadence": cadence(schema_rows.get(INTERVAL_SCHEMA, []), args.presentation_metric, args.hitch_reference_hz) if INTERVAL_SCHEMA in schema_rows else {"available": False, "reason": "missing presentation interval schema"},
            "cpu_frame_metric": named_metric(frame_rows, args.cpu_metric) if frame_rows else {"available": False, "reason": "missing named frame metric schemas"},
            "gpu_frame_metric": named_metric(frame_rows, args.gpu_metric) if frame_rows else {"available": False, "reason": "missing named frame metric schemas"},
            "sampled_cpu": sampled_cpu(schema_rows[CPU_SCHEMA], provenance["duration_seconds"]) if CPU_SCHEMA in schema_rows else {"available": False, "reason": "missing Time Profiler schema"},
            "thermal": thermal(schema_rows[THERMAL_SCHEMA]) if THERMAL_SCHEMA in schema_rows else {"available": False, "reason": "missing thermal schema"},
        },
    }
    (args.output / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    with (args.output / "report.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=["category", "available", "name", "label", "sample_count", "mean_ms", "p95_ms", "max_ms", "detail"])
        writer.writeheader()
        writer.writerows(compact_rows(report))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AnalysisError as error:
        print(f"analyze-ios-game-performance: {error}", file=sys.stderr)
        raise SystemExit(2)
