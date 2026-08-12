#!/usr/bin/env python3
"""Synthetic checks for the offline schema-v2 cross-run comparator."""

import copy
import json
import math
import subprocess
import tempfile
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parent
COMPARE = ROOT / "compare-ios-game-performance.py"
LABEL_MODES = (("60-A", "60"), ("HFR-A", "hfr"), ("HFR-B", "hfr"), ("60-B", "60"))
CADENCE_HZ = (120, 80, 60, 48, 40, 30, 24)
CONTRACT = {
    "analyzer_version": 2,
    "cadence_hz": list(CADENCE_HZ),
    "classifier_tolerance_fraction": 0.08,
    "histogram_unit": "ns",
    "high_refresh_definition": "classified_hz > 60",
    "candidate_multipliers": [1.5, 2, 3],
    "percentile_method": "nearest-rank",
    "non_shipping": True,
    "no_hitch_verdict": True,
    "runtime_settings_source": "operator",
}


def classify(duration_ns):
    interval_ms = duration_ns / 1_000_000
    closest = min(CADENCE_HZ, key=lambda hz: abs(interval_ms - 1000.0 / hz))
    ideal = 1000.0 / closest
    return str(closest) if abs(interval_ms - ideal) <= ideal * 0.08 else "unclassified"


def percentile(durations, fraction):
    ordered = sorted(durations)
    return round(ordered[max(0, math.ceil(len(ordered) * fraction) - 1)] / 1_000_000, 6)


def cadence_payload(mode, high_refresh=True):
    durations = [12_500_000, 12_500_000, 12_500_000, 16_666_667] if mode == "hfr" and high_refresh else [16_666_667] * 4
    histogram = Counter(durations)
    classifications = [classify(duration) for duration in durations]
    clusters = Counter(classifications)
    cluster_durations = Counter()
    for classification, duration in zip(classifications, durations):
        cluster_durations[classification] += duration
    runs = []
    for classification, duration in zip(classifications, durations):
        if runs and runs[-1]["classification"] == classification:
            runs[-1]["sample_count"] += 1
            runs[-1]["total_duration_ns"] += duration
        else:
            runs.append({"classification": classification, "sample_count": 1, "total_duration_ns": duration})
    total = sum(durations)
    high_count = sum(1 for classification in classifications if classification != "unclassified" and int(classification) > 60)
    high_duration = sum(duration for classification, duration in zip(classifications, durations) if classification != "unclassified" and int(classification) > 60)
    reference_ms = 1000.0 / 120
    thresholds = {
        name: sum(duration / 1_000_000 >= reference_ms * multiplier for duration in durations)
        for name, multiplier in zip(("1.5x", "2x", "3x"), (1.5, 2, 3))
    }
    source = {
        "schema": "metal-perf-overview-layer-per-frame-interval-metric",
        "name": "Presented Frames",
        "label": "Presentation interval",
        "value_column": "duration",
        "observed_cell_tags": ["duration"],
        "unit": "ms",
    }
    return {
        "available": True,
        **source,
        "source": source,
        "sample_count": len(durations),
        "mean_ms": round(total / len(durations) / 1_000_000, 6),
        "p50_ms": percentile(durations, 0.50),
        "p95_ms": percentile(durations, 0.95),
        "p99_ms": percentile(durations, 0.99),
        "max_ms": round(max(durations) / 1_000_000, 6),
        "interval_histogram_ns": {str(key): value for key, value in sorted(histogram.items())},
        "total_duration_ns": total,
        "min_duration_ns": min(durations),
        "cadence_clusters": {str(hz): clusters[str(hz)] for hz in CADENCE_HZ},
        "cadence_cluster_total_duration_ns": {str(hz): cluster_durations[str(hz)] for hz in CADENCE_HZ},
        "unclassified": clusters["unclassified"],
        "unclassified_total_duration_ns": cluster_durations["unclassified"],
        "cadence_runs": runs,
        "high_refresh_above_60": {
            "sample_count": high_count,
            "sample_share": round(high_count / len(durations), 6),
            "total_duration_ns": high_duration,
            "duration_share": round(high_duration / total, 6),
        },
        "multi_interval_hitch_candidates": {
            "available": True,
            "candidate_only": True,
            "note": "Candidates include legitimate adaptive cadence transitions.",
            "reference_hz": 120,
            "count": thresholds["1.5x"],
            "threshold_ms": 12.5,
            "thresholds": thresholds,
        },
    }


def thermal_payload(state="Nominal", duration_seconds=30):
    return {
        "available": True,
        "intervals": [{"start_ns": 0, "duration_ms": duration_seconds * 1000, "state": state}],
        "state_sample_counts": {state: 1},
        "state_total_duration_ns": {state: duration_seconds * 1_000_000_000},
    }


def report(label, mode, high_refresh=True):
    return {
        "schema_version": 2,
        "process_filter": "Dark Eco",
        "analysis_contract": copy.deepcopy(CONTRACT),
        "provenance": {
            "duration_seconds": 30,
            "capture_metadata": {
                "device": "Z iPad Pro",
                "outer_head": "outer",
                "nested_head": "nested",
                "template": "Game Performance Overview",
                "xctrace_version": "xctrace version 16",
                "process": "Dark Eco",
                "kind": "overview",
                "duration": "30s",
                "mode": mode,
            },
        },
        "comparison_context": {
            "source": "operator",
            "run_label": label,
            "route_id": "spider-cave-marker",
            "graphics_profile": "Modern",
            "resolution": "2x",
            "input": "DualSense",
            "brightness": "fixed-50-percent",
            "low_power_mode": False,
            "developer_logs": False,
            "nominal_start_thermal_state": "Nominal",
            "installed_build_artifact": "Dark Eco 1.0 (207), CoreDevice inventory verified",
        },
        "measurements": {
            "cadence": cadence_payload(mode, high_refresh),
            "cpu_frame_metric": {"available": False},
            "gpu_frame_metric": {"available": False},
            "thermal": thermal_payload(),
            "sampled_cpu": {"available": False},
        },
    }


def fresh_reports(high_refresh=True):
    return [report(label, mode, high_refresh if mode == "hfr" else False) for label, mode in LABEL_MODES]


def run(root, name, reports):
    case = root / name
    case.mkdir()
    paths = []
    for (label, _), value in zip(LABEL_MODES, reports):
        path = case / f"{label}.json"
        path.write_text(json.dumps(value), encoding="utf-8")
        paths.append(path)
    output = root / f"{name}-output"
    command = ["python3", str(COMPARE), "--60-a", str(paths[0]), "--hfr-a", str(paths[1]), "--hfr-b", str(paths[2]), "--60-b", str(paths[3]), "--output", str(output)]
    return subprocess.run(command, text=True, capture_output=True), output


def expect_failure(root, name, mutate, message):
    reports = fresh_reports()
    mutate(reports)
    result, output = run(root, name, reports)
    assert result.returncode == 2, (name, result.stdout, result.stderr)
    assert message in result.stderr, (name, result.stderr)
    assert not output.exists(), name


def main():
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        result, output = run(root, "valid", fresh_reports())
        assert result.returncode == 0, result.stderr
        comparison = json.loads((output / "comparison.json").read_text())
        assert comparison["evidence_sufficiency"]["HFR_observed_above_60_in_both_reps"]
        assert comparison["evidence_sufficiency"]["60_cadence_observed_in_both_reps"]
        assert comparison["modes"]["hfr"]["pooled_interval_percentiles_ms"]["p50_ms"] == 12.5
        assert comparison["modes"]["hfr"]["above_60_sample_share"] == 0.75
        assert comparison["modes"]["hfr"]["above_60_duration_share"] == 0.692308
        assert comparison["modes"]["hfr"]["above_60_sample_share"] != comparison["modes"]["hfr"]["above_60_duration_share"]
        assert "above_60_duration_share" in (output / "comparison.csv").read_text()

        repeat, repeat_output = run(root, "repeat", fresh_reports())
        assert repeat.returncode == 0, repeat.stderr
        assert (output / "comparison.json").read_text() == (repeat_output / "comparison.json").read_text()
        assert (output / "comparison.csv").read_text() == (repeat_output / "comparison.csv").read_text()

        result, no_hfr_output = run(root, "no-high-refresh", fresh_reports(high_refresh=False))
        assert result.returncode == 0, result.stderr
        no_hfr = json.loads((no_hfr_output / "comparison.json").read_text())
        assert not no_hfr["evidence_sufficiency"]["HFR_observed_above_60_in_both_reps"]

        expect_failure(root, "schema", lambda values: values[2].__setitem__("schema_version", 1), "schema_version 2")
        expect_failure(root, "device", lambda values: values[2]["provenance"]["capture_metadata"].__setitem__("device", "Other"), "device differs")
        expect_failure(root, "outer", lambda values: values[2]["provenance"]["capture_metadata"].__setitem__("outer_head", "other"), "outer_head differs")
        expect_failure(root, "mode", lambda values: values[1]["provenance"]["capture_metadata"].__setitem__("mode", "60"), "mode does not match")
        expect_failure(root, "kind", lambda values: values[1]["provenance"]["capture_metadata"].__setitem__("kind", "metal"), "kind=overview")
        expect_failure(root, "requested-duration", lambda values: values[2]["provenance"]["capture_metadata"].__setitem__("duration", "31s"), "duration differs")
        expect_failure(root, "template", lambda values: values[2]["provenance"]["capture_metadata"].__setitem__("template", "Other"), "Game Performance Overview")
        expect_failure(root, "process", lambda values: values[2]["provenance"]["capture_metadata"].__setitem__("process", "Other"), "process must be Dark Eco")
        expect_failure(root, "xctrace", lambda values: values[2]["provenance"]["capture_metadata"].__setitem__("xctrace_version", "other"), "xctrace_version differs")
        expect_failure(root, "actual-duration", lambda values: values[2]["provenance"].__setitem__("duration_seconds", 32), "actual TOC durations differ")
        expect_failure(root, "contract", lambda values: values[2]["analysis_contract"].__setitem__("classifier_tolerance_fraction", 0.1), "analysis_contract")
        expect_failure(root, "context", lambda values: values[2]["comparison_context"].__setitem__("graphics_profile", "Classic"), "comparison context graphics_profile differs")
        expect_failure(root, "artifact", lambda values: values[2]["comparison_context"].__setitem__("installed_build_artifact", "Other"), "installed_build_artifact differs")
        expect_failure(root, "context-source", lambda values: values[2]["comparison_context"].__setitem__("source", "inferred"), "operator comparison_context")
        expect_failure(root, "run-label", lambda values: values[2]["comparison_context"].__setitem__("run_label", "HFR-A"), "run_label")
        expect_failure(root, "cadence-unavailable", lambda values: values[2]["measurements"]["cadence"].__setitem__("available", False), "available cadence")
        expect_failure(root, "cadence-tag", lambda values: values[2]["measurements"]["cadence"].__setitem__("observed_cell_tags", ["fixed-decimal"]), "source does not match")
        expect_failure(root, "histogram", lambda values: values[2]["measurements"]["cadence"]["interval_histogram_ns"].__setitem__("12500000", 4), "histogram does not reconcile")
        expect_failure(root, "clusters", lambda values: values[2]["measurements"]["cadence"]["cadence_clusters"].__setitem__("80", 2), "clusters do not reconcile")
        expect_failure(root, "high-summary", lambda values: values[2]["measurements"]["cadence"]["high_refresh_above_60"].__setitem__("sample_count", 2), "high-refresh summary")
        expect_failure(root, "runs", lambda values: values[2]["measurements"]["cadence"]["cadence_runs"][0].__setitem__("sample_count", 2), "cadence runs")
        expect_failure(root, "candidates", lambda values: values[2]["measurements"]["cadence"]["multi_interval_hitch_candidates"]["thresholds"].__setitem__("2x", 99), "candidate thresholds")
        expect_failure(root, "thermal-unavailable", lambda values: values[2]["measurements"]["thermal"].__setitem__("available", False), "available thermal")
        expect_failure(root, "thermal-late", lambda values: values[2]["measurements"]["thermal"]["intervals"][0].__setitem__("start_ns", 2_000_000_000), "begin near trace start")

        def overlap(values):
            values[2]["measurements"]["thermal"] = {
                "available": True,
                "intervals": [{"start_ns": 0, "duration_ms": 20_000, "state": "Nominal"}, {"start_ns": 19_000_000_000, "duration_ms": 11_000, "state": "Nominal"}],
                "state_sample_counts": {"Nominal": 2}, "state_total_duration_ns": {"Nominal": 31_000_000_000},
            }
        expect_failure(root, "thermal-overlap", overlap, "unordered or overlapping")

        def gap(values):
            values[2]["measurements"]["thermal"] = {
                "available": True,
                "intervals": [{"start_ns": 0, "duration_ms": 10_000, "state": "Nominal"}, {"start_ns": 10_100_000_000, "duration_ms": 19_900, "state": "Nominal"}],
                "state_sample_counts": {"Nominal": 2}, "state_total_duration_ns": {"Nominal": 29_900_000_000},
            }
        expect_failure(root, "thermal-gap", gap, "unordered or overlapping")

        expect_failure(root, "thermal-end", lambda values: values[2]["measurements"]["thermal"]["intervals"][0].__setitem__("duration_ms", 20_000), "do not cover")

        def pair_state(values):
            values[1]["comparison_context"]["nominal_start_thermal_state"] = "Fair"
            values[1]["measurements"]["thermal"] = thermal_payload("Fair")
        expect_failure(root, "pair-state", pair_state, "counterbalanced pair")

    print("ios-game-performance-comparison-check: PASS")


if __name__ == "__main__":
    main()
