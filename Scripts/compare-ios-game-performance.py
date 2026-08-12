#!/usr/bin/env python3
"""Offline, non-shipping comparison of four schema-v2 Dark Eco analysis reports."""

import argparse
import csv
import json
import math
import statistics
import sys
from collections import Counter
from pathlib import Path


LABELS = ("60-A", "HFR-A", "HFR-B", "60-B")
CONTEXT_EQUAL = ("route_id", "graphics_profile", "resolution", "input", "brightness", "low_power_mode", "developer_logs")
CONTEXT_REQUIRED = CONTEXT_EQUAL + ("nominal_start_thermal_state",)
CONTRACT = {"analyzer_version": 2, "cadence_hz": [120, 80, 60, 48, 40, 30, 24], "classifier_tolerance_fraction": 0.08, "histogram_unit": "ns", "high_refresh_definition": "classified_hz > 60", "candidate_multipliers": [1.5, 2, 3], "percentile_method": "nearest-rank", "non_shipping": True, "no_hitch_verdict": True, "runtime_settings_source": "operator"}
THERMAL_TOLERANCE_NS = 1_000_000_000
THERMAL_GAP_TOLERANCE_NS = 1_000_000


class CompareError(RuntimeError):
    pass


def load(label, path):
    try:
        report = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise CompareError(f"{label}: invalid report: {error}") from error
    if report.get("schema_version") != 2:
        raise CompareError(f"{label}: schema_version 2 is required")
    if report.get("process_filter") != "Dark Eco":
        raise CompareError(f"{label}: process_filter must be Dark Eco")
    if report.get("analysis_contract") != CONTRACT:
        raise CompareError(f"{label}: analysis_contract is missing or differs")
    context = report.get("comparison_context")
    if (not isinstance(context, dict) or context.get("source") != "operator"
            or context.get("run_label") != label
            or any(field not in context for field in CONTEXT_REQUIRED)
            or context.get("low_power_mode") is not False
            or context.get("developer_logs") is not False
            or not isinstance(context.get("installed_build_artifact"), str)
            or not context["installed_build_artifact"]):
        raise CompareError(f"{label}: operator comparison_context/run_label does not match the explicit input label")
    cadence = report.get("measurements", {}).get("cadence", {})
    if not cadence.get("available") or not cadence.get("sample_count") or not cadence.get("interval_histogram_ns"):
        raise CompareError(f"{label}: available cadence with exact interval histogram is required")
    required = ("schema", "name", "label", "value_column", "observed_cell_tags", "unit")
    if cadence.get("source") is None or any(cadence.get(key) is None for key in required) or cadence["unit"] != "ms":
        raise CompareError(f"{label}: cadence metric identity/unit is incomplete")
    if cadence["source"] != {key: cadence[key] for key in required}:
        raise CompareError(f"{label}: cadence source does not match direct identity")
    if (cadence["schema"] != "metal-perf-overview-layer-per-frame-interval-metric"
            or cadence["value_column"] != "duration"
            or cadence["observed_cell_tags"] != ["duration"]
            or not cadence["name"] or not cadence["label"]):
        raise CompareError(f"{label}: cadence source is not the supported presentation interval metric shape")
    try:
        histogram = {int(key): int(value) for key, value in cadence["interval_histogram_ns"].items()}
    except (AttributeError, TypeError, ValueError) as error:
        raise CompareError(f"{label}: cadence histogram is malformed") from error
    if not histogram or any(duration <= 0 or count <= 0 for duration, count in histogram.items()):
        raise CompareError(f"{label}: cadence histogram requires positive durations and counts")
    if sum(histogram.values()) != cadence["sample_count"] or sum(key * value for key, value in histogram.items()) != cadence.get("total_duration_ns"):
        raise CompareError(f"{label}: cadence histogram does not reconcile")
    expected_clusters, expected_cluster_durations = classify_histogram(histogram)
    reported_clusters = cadence.get("cadence_clusters")
    reported_cluster_durations = cadence.get("cadence_cluster_total_duration_ns")
    if reported_clusters != {str(hz): expected_clusters[str(hz)] for hz in CONTRACT["cadence_hz"]} or cadence.get("unclassified") != expected_clusters["unclassified"]:
        raise CompareError(f"{label}: cadence clusters do not reconcile with histogram")
    if reported_cluster_durations != {str(hz): expected_cluster_durations[str(hz)] for hz in CONTRACT["cadence_hz"]} or cadence.get("unclassified_total_duration_ns") != expected_cluster_durations["unclassified"]:
        raise CompareError(f"{label}: cadence cluster durations do not reconcile with histogram")
    validate_cadence_runs(label, cadence, expected_clusters, expected_cluster_durations)
    high = cadence.get("high_refresh_above_60", {})
    expected_high_count = sum(expected_clusters[str(hz)] for hz in CONTRACT["cadence_hz"] if hz > 60)
    expected_high_duration = sum(expected_cluster_durations[str(hz)] for hz in CONTRACT["cadence_hz"] if hz > 60)
    if (high.get("sample_count") != expected_high_count or high.get("total_duration_ns") != expected_high_duration
            or high.get("sample_share") != round(expected_high_count / cadence["sample_count"], 6)
            or high.get("duration_share") != round(expected_high_duration / cadence["total_duration_ns"], 6)):
        raise CompareError(f"{label}: high-refresh summary does not reconcile")
    expected_summary = percentiles(histogram)
    expected_mean = round(cadence["total_duration_ns"] / cadence["sample_count"] / 1_000_000, 6)
    for key, value in expected_summary.items():
        if cadence.get(key) != value:
            raise CompareError(f"{label}: cadence {key} does not reconcile with histogram")
    if cadence.get("mean_ms") != expected_mean or cadence.get("min_duration_ns") != min(histogram):
        raise CompareError(f"{label}: cadence mean/minimum does not reconcile with histogram")
    candidate = cadence.get("multi_interval_hitch_candidates", {})
    if not candidate.get("available") or set(candidate.get("thresholds", {})) != {"1.5x", "2x", "3x"} or candidate.get("reference_hz") is None or candidate.get("threshold_ms") is None:
        raise CompareError(f"{label}: candidate threshold semantics are incomplete")
    if candidate.get("candidate_only") is not True or not candidate.get("note"):
        raise CompareError(f"{label}: candidate-only semantics are incomplete")
    reference_hz = candidate["reference_hz"]
    if reference_hz not in CONTRACT["cadence_hz"]:
        raise CompareError(f"{label}: candidate reference cadence is unsupported")
    reference_ms = 1000.0 / reference_hz
    expected_thresholds = {
        name: sum(count for duration, count in histogram.items() if duration / 1_000_000 >= reference_ms * multiplier)
        for name, multiplier in zip(("1.5x", "2x", "3x"), CONTRACT["candidate_multipliers"])
    }
    if candidate["thresholds"] != expected_thresholds or candidate.get("count") != expected_thresholds["1.5x"] or candidate["threshold_ms"] != round(reference_ms * 1.5, 6):
        raise CompareError(f"{label}: candidate thresholds do not reconcile with histogram")
    return report


def classify_duration(duration_ns):
    interval_ms = duration_ns / 1_000_000
    closest = min(CONTRACT["cadence_hz"], key=lambda hz: abs(interval_ms - 1000.0 / hz))
    ideal = 1000.0 / closest
    return str(closest) if abs(interval_ms - ideal) <= ideal * CONTRACT["classifier_tolerance_fraction"] else "unclassified"


def classify_histogram(histogram):
    counts = Counter()
    durations = Counter()
    for duration_ns, count in histogram.items():
        classification = classify_duration(duration_ns)
        counts[classification] += count
        durations[classification] += duration_ns * count
    return counts, durations


def validate_cadence_runs(label, cadence, expected_counts, expected_durations):
    runs = cadence.get("cadence_runs")
    if not isinstance(runs, list) or not runs:
        raise CompareError(f"{label}: cadence runs are missing")
    counts = Counter()
    durations = Counter()
    previous = None
    allowed = {str(hz) for hz in CONTRACT["cadence_hz"]} | {"unclassified"}
    for run in runs:
        classification = run.get("classification") if isinstance(run, dict) else None
        count = run.get("sample_count") if isinstance(run, dict) else None
        duration = run.get("total_duration_ns") if isinstance(run, dict) else None
        if classification not in allowed or not isinstance(count, int) or count <= 0 or not isinstance(duration, int) or duration <= 0 or classification == previous:
            raise CompareError(f"{label}: cadence runs are malformed or not contiguous")
        counts[classification] += count
        durations[classification] += duration
        previous = classification
    if counts != expected_counts or durations != expected_durations:
        raise CompareError(f"{label}: cadence runs do not reconcile with histogram")


def identity(report):
    provenance = report.get("provenance", {})
    metadata = provenance.get("capture_metadata", {})
    fields = {
        "device": metadata.get("device"), "outer_head": metadata.get("outer_head"),
        "nested_head": metadata.get("nested_head"), "template": metadata.get("template") or provenance.get("template"),
        "xctrace_version": metadata.get("xctrace_version") or provenance.get("xctrace_version"),
        "process": metadata.get("process"),
        "kind": metadata.get("kind"), "duration": metadata.get("duration"), "mode": metadata.get("mode"),
    }
    missing = [key for key, value in fields.items() if not value]
    if missing:
        raise CompareError("capture metadata missing required " + ", ".join(missing))
    if fields["process"] != "Dark Eco":
        raise CompareError("capture metadata process must be Dark Eco")
    if fields["template"] != "Game Performance Overview":
        raise CompareError("cadence comparator requires the Game Performance Overview template")
    return fields


def same(name, values):
    if len(set(json.dumps(value, sort_keys=True) for value in values)) != 1:
        raise CompareError(f"reports are not comparable: {name} differs")
    return values[0]


def metric_identity(value):
    if not value.get("available"):
        return None
    source = value.get("source")
    keys = ("schema", "name", "label", "value_column", "observed_cell_tags", "unit")
    if not isinstance(source, dict) or any(source.get(key) is None for key in keys):
        return None
    return {key: source[key] for key in keys}


def percentiles(histogram):
    values = sorted((int(key), int(value)) for key, value in histogram.items())
    count = sum(value for _, value in values)
    def one(fraction):
        target = max(1, math.ceil(count * fraction)); seen = 0
        for value, weight in values:
            seen += weight
            if seen >= target: return round(value / 1_000_000, 6)
    return {"p50_ms": one(.5), "p95_ms": one(.95), "p99_ms": one(.99), "max_ms": round(values[-1][0] / 1_000_000, 6)}


def validate_thermal(label, report):
    thermal = report["measurements"].get("thermal", {})
    duration = report["provenance"].get("duration_seconds")
    if not thermal.get("available") or not duration:
        raise CompareError(f"{label}: available thermal intervals and trace duration are required")
    intervals = thermal.get("intervals", [])
    if not intervals or intervals[0].get("start_ns", THERMAL_TOLERANCE_NS + 1) > THERMAL_TOLERANCE_NS:
        raise CompareError(f"{label}: thermal intervals must begin near trace start")
    previous = None
    state_counts = Counter()
    state_durations = Counter()
    for interval in intervals:
        start = interval.get("start_ns"); duration_ms = interval.get("duration_ms")
        state = interval.get("state")
        if (not isinstance(start, int) or start < 0 or not isinstance(duration_ms, (int, float))
                or duration_ms <= 0 or not isinstance(state, str) or not state):
            raise CompareError(f"{label}: thermal interval is malformed")
        if previous is not None and (start < previous or start - previous > THERMAL_GAP_TOLERANCE_NS):
            raise CompareError(f"{label}: thermal intervals are unordered or overlapping")
        previous = start + round(duration_ms * 1_000_000)
        state_counts[state] += 1
        state_durations[state] += round(duration_ms * 1_000_000)
    if abs(previous - round(float(duration) * 1_000_000_000)) > THERMAL_TOLERANCE_NS:
        raise CompareError(f"{label}: thermal intervals do not cover the trace within tolerance")
    if thermal.get("state_sample_counts") != dict(sorted(state_counts.items())) or thermal.get("state_total_duration_ns") != dict(sorted(state_durations.items())):
        raise CompareError(f"{label}: thermal summaries do not reconcile")
    expected_start = report["comparison_context"]["nominal_start_thermal_state"]
    if intervals[0]["state"] != expected_start:
        raise CompareError(f"{label}: observed thermal start does not match operator context")
    return thermal


def run_summary(label, report):
    cadence = report["measurements"]["cadence"]
    count = cadence["sample_count"]
    clusters = cadence["cadence_clusters"]
    unclassified = cadence.get("unclassified", 0)
    high = cadence["high_refresh_above_60"]
    candidates = cadence.get("multi_interval_hitch_candidates", {})
    return {
        "label": label, "mode": "hfr" if label.startswith("HFR") else "60",
        "sample_count": count, "interval_summary_ms": {key: cadence.get(key) for key in ("p50_ms", "p95_ms", "p99_ms", "max_ms")},
        "total_duration_ns": cadence["total_duration_ns"], "interval_histogram_ns": cadence["interval_histogram_ns"],
        "cadence_cluster_counts": clusters,
        "cadence_cluster_shares": {key: round(value / count, 6) for key, value in sorted(clusters.items())},
        "unclassified_count": unclassified, "unclassified_share": round(unclassified / count, 6),
        "above_60": high, "contiguous_runs": cadence["cadence_runs"],
        "candidate_counts": candidates.get("thresholds") if candidates.get("available") else None,
        "candidate_caveat": candidates.get("note", "No candidate threshold was supplied; this is not a hitch verdict."),
        "thermal": report["measurements"].get("thermal"), "sampled_cpu": report["measurements"].get("sampled_cpu"),
    }


def mode_summary(mode, runs):
    count = sum(run["sample_count"] for run in runs)
    clusters = Counter()
    unclassified = 0
    high_count = high_duration = duration = 0
    histogram = Counter()
    candidates = Counter()
    for run in runs:
        clusters.update(run["cadence_cluster_counts"])
        unclassified += run["unclassified_count"]
        high_count += run["above_60"]["sample_count"]
        high_duration += run["above_60"]["total_duration_ns"]
        duration += run["total_duration_ns"]
        histogram.update(run["interval_histogram_ns"])
        if run["candidate_counts"]:
            candidates.update(run["candidate_counts"])
    return {"mode": mode, "replicate_count": len(runs), "sample_count": count,
            "cadence_cluster_counts": dict(sorted(clusters.items())),
            "cadence_cluster_shares": {key: round(value / count, 6) for key, value in sorted(clusters.items())},
            "above_60_sample_share": round(high_count / count, 6), "above_60_duration_share": round(high_duration / duration, 6), "unclassified_share": round(unclassified / count, 6),
            "candidate_counts": dict(sorted(candidates.items())),
            "pooled_interval_percentiles_ms": percentiles(histogram), "pooled_interval_histogram_ns": dict(sorted(histogram.items(), key=lambda pair: int(pair[0]))),
            "median_of_run_percentiles_ms": {key: statistics.median([run["interval_summary_ms"][key] for run in runs]) for key in ("p50_ms", "p95_ms", "p99_ms", "max_ms") if all(run["interval_summary_ms"][key] is not None for run in runs)}}


def optional_metric(reports, category):
    values = [report["measurements"].get(category, {}) for report in reports]
    identities = [metric_identity(value) for value in values]
    if any(identity is None for identity in identities):
        return {"available": False, "reason": "both replicates in each mode must expose the metric"}
    identity = same(f"{category} metric identity", identities)
    return {"available": True, "identity": identity, "per_run": [{"label": label, **{key: report["measurements"][category].get(key) for key in ("sample_count", "mean_ms", "p50_ms", "p95_ms", "p99_ms", "max_ms")}} for label, report in zip(LABELS, reports)]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for label in LABELS:
        parser.add_argument("--" + label.lower(), required=True, type=Path, dest=label.lower().replace("-", "_"))
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.output.exists():
        raise CompareError(f"output already exists: {args.output}")
    reports = [load(label, getattr(args, label.lower().replace("-", "_"))) for label in LABELS]
    identities = [identity(report) for report in reports]
    for label, item in zip(LABELS, identities):
        expected_mode = "hfr" if label.startswith("HFR") else "60"
        if item["mode"] != expected_mode:
            raise CompareError(f"{label}: capture metadata mode does not match label")
        if item["kind"] != "overview":
            raise CompareError(f"{label}: cadence comparator requires metadata kind=overview")
    common_identity = {key: same(key, [value[key] for value in identities]) for key in identities[0] if key != "mode"}
    try:
        trace_durations = [float(report["provenance"].get("duration_seconds")) for report in reports]
    except (TypeError, ValueError) as error:
        raise CompareError("actual TOC durations must be numeric") from error
    if any(not math.isfinite(duration) or duration <= 0 for duration in trace_durations):
        raise CompareError("actual TOC durations must be positive and finite")
    if max(trace_durations) - min(trace_durations) > 1.0:
        raise CompareError("actual TOC durations differ by more than one second")
    contexts = [report["comparison_context"] for report in reports]
    common_context = {key: same("comparison context " + key, [context[key] for context in contexts]) for key in CONTEXT_EQUAL + ("installed_build_artifact",)}
    cadence_identity = same("cadence metric identity", [metric_identity(report["measurements"]["cadence"]) for report in reports])
    candidate_identity = same("candidate threshold semantics", [{key: report["measurements"]["cadence"].get("multi_interval_hitch_candidates", {}).get(key) for key in ("reference_hz", "threshold_ms", "candidate_only", "note")} for report in reports])
    thermals = [validate_thermal(label, report) for label, report in zip(LABELS, reports)]
    for left, right in ((0, 1), (2, 3)):
        if thermals[left]["intervals"][0].get("state") != thermals[right]["intervals"][0].get("state"):
            raise CompareError("thermal initial state differs within a counterbalanced pair")
    summaries = [run_summary(label, report) for label, report in zip(LABELS, reports)]
    by_mode = {mode: mode_summary(mode, [run for run in summaries if run["mode"] == mode]) for mode in ("60", "hfr")}
    hfr_runs = [run for run in summaries if run["mode"] == "hfr"]
    baseline_runs = [run for run in summaries if run["mode"] == "60"]
    result = {"schema_version": 1, "non_shipping": True, "comparable": True,
              "identity": common_identity, "comparison_context": {**common_context, "source": "operator",
                "nominal_start_thermal_state_by_run": {label: context["nominal_start_thermal_state"] for label, context in zip(LABELS, contexts)}},
              "cadence_metric": cadence_identity, "candidate_semantics": candidate_identity, "runs": summaries, "modes": by_mode, "thermal": {label: thermal.get("state_total_duration_ns") for label, thermal in zip(LABELS, thermals)},
              "cpu_frame_metric": optional_metric(reports, "cpu_frame_metric"), "gpu_frame_metric": optional_metric(reports, "gpu_frame_metric"),
              "evidence_sufficiency": {"HFR_observed_above_60_in_both_reps": all(run["above_60"]["sample_count"] > 0 for run in hfr_runs),
                "60_cadence_observed_in_both_reps": all(run["cadence_cluster_shares"].get("60", 0) > 0 for run in baseline_runs),
                "installed_binary_identity": common_context["installed_build_artifact"],
                "missing_physical_correctness_fields": ["camera", "timers", "dialogue_audio", "controller_touch", "save_completion", "rumble"],
                "missing_power_fields": ["sustained Power Profiler comparison"],
                "verdict": "Evidence sufficiency only; no performance acceptance or hitch-regression threshold is inferred."}}
    args.output.mkdir(parents=True)
    (args.output / "comparison.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    rows = [{"label": run["label"], "mode": run["mode"], "sample_count": run["sample_count"], "above_60_sample_share": run["above_60"]["sample_share"], "above_60_duration_share": run["above_60"]["duration_share"], "unclassified_share": run["unclassified_share"], **run["interval_summary_ms"]} for run in summaries]
    with (args.output / "comparison.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=["label", "mode", "sample_count", "above_60_sample_share", "above_60_duration_share", "unclassified_share", "p50_ms", "p95_ms", "p99_ms", "max_ms"])
        writer.writeheader(); writer.writerows(rows)


if __name__ == "__main__":
    try: main()
    except CompareError as error:
        print("compare-ios-game-performance: " + str(error), file=sys.stderr); raise SystemExit(2)
