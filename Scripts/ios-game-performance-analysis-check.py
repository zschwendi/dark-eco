#!/usr/bin/env python3
"""Synthetic, copyright-clean checks for analyze-ios-game-performance.py."""

import json
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent
ANALYZER = ROOT / "analyze-ios-game-performance.py"


def write(path, content):
    path.write_text(content, encoding="utf-8")


def query(schema, columns, rows):
    header = "".join(f"<col><mnemonic>{column}</mnemonic></col>" for column in columns)
    body = "".join(f"<row>{row}</row>" for row in rows)
    return f'<?xml version="1.0"?><trace-query-result><node><schema name="{schema}">{header}</schema>{body}</node></trace-query-result>'


def cells(*items):
    return "".join(items)


def cell(tag, value, fmt=None, identifier=None, ref=None):
    attrs = ""
    if fmt is not None:
        attrs += f' fmt="{fmt}"'
    if identifier is not None:
        attrs += f' id="{identifier}"'
    if ref is not None:
        return f'<{tag} ref="{ref}"/>'
    return f"<{tag}{attrs}>{value}</{tag}>"


def main():
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        capture = root / "capture"
        capture.mkdir()
        write(capture / "dark-eco-build207-hfr-metadata.txt", "mode=hfr\nxctrace_version=16.0\nouter_head=f27f8633\n")
        write(capture / "dark-eco-build207-hfr-toc.xml", '''<trace-toc><run number="1"><info><summary><template-name>Game Performance Overview</template-name><instruments-version>16.0 (17F113)</instruments-version><duration fmt="30.00 s">30</duration></summary></info><data>
<table schema="metal-perf-overview-layer-per-frame-metric"/><table schema="metal-perf-overview-layer-per-frame-interval-metric"/><table schema="time-profile"/><table schema="device-thermal-state-intervals"/><table schema="future-schema"/></data></run></trace-toc>''')
        write(capture / "metal-perf-overview-layer-per-frame-interval-metric.xml", query(
            "metal-perf-overview-layer-per-frame-interval-metric",
            ["duration", "name", "label", "process-name"],
            [cells(cell("duration", "8333333", fmt="8.33 ms", identifier="frame-120"), cell("string", "1", fmt="Presented Frames"), cell("string", "2", fmt="Presentation interval"), cell("process-name", "77", fmt="Dark Eco", identifier="eco")),
             cells(cell("duration", "", ref="frame-120"), cell("string", "1", fmt="Presented Frames"), cell("string", "2", fmt="Presentation interval"), cell("process-name", "", ref="eco")),
             cells(cell("duration", "16666666", fmt="16.67 ms"), cell("string", "1", fmt="Presented Frames"), cell("string", "2", fmt="Presentation interval"), cell("process-name", "77", fmt="Dark Eco")),
             cells(cell("duration", "33333332", fmt="33.33 ms"), cell("string", "1", fmt="Presented Frames"), cell("string", "2", fmt="Presentation interval"), cell("process-name", "77", fmt="Dark Eco")),
             cells(cell("duration", "8333333", fmt="8.33 ms"), cell("string", "3", fmt="Other"), cell("string", "4", fmt="Other interval"), cell("process-name", "88", fmt="Not Dark Eco"))]))
        write(capture / "metal-perf-overview-layer-per-frame-metric.xml", query(
            "metal-perf-overview-layer-per-frame-metric",
            ["metric-value", "name", "label", "process-name"],
            [cells(cell("duration", "4000000", fmt="4.00 ms", identifier="cpu-value"), cell("string", "10", fmt="CPU Frame Time"), cell("string", "11", fmt="CPU frame"), cell("process-name", "77", fmt="Dark Eco")),
             cells(cell("duration", "", ref="cpu-value"), cell("string", "10", fmt="CPU Frame Time"), cell("string", "11", fmt="CPU frame"), cell("process-name", "77", fmt="Dark Eco")),
             cells(cell("duration", "6000000", fmt="6.00 ms"), cell("string", "12", fmt="GPU Frame Time"), cell("string", "13", fmt="GPU frame"), cell("process-name", "77", fmt="Dark Eco")),
             cells(cell("fixed-decimal", "7.0", fmt="7.00"), cell("string", "14", fmt="Unspecified Metric"), cell("string", "15", fmt="unspecified"), cell("process-name", "77", fmt="Dark Eco")),
             cells(cell("duration", "99000000", fmt="99.00 ms"), cell("string", "12", fmt="GPU Frame Time"), cell("string", "13", fmt="GPU frame"), cell("process-name", "88", fmt="Other"))]))
        write(capture / "time-profile.xml", query(
            "time-profile", ["thread-state", "weight", "stack", "process"],
            [cells(cell("thread-state", "1", fmt="Running"), cell("weight", "1000000", fmt="1.00 ms", identifier="weight"), '<tagged-backtrace fmt="hot_function"><backtrace/></tagged-backtrace>', '<process id="process" fmt="Dark Eco (77)"><pid>77</pid></process>'),
             cells(cell("thread-state", "1", fmt="Running"), cell("weight", "", ref="weight"), '<tagged-backtrace fmt="hot_function"><backtrace/></tagged-backtrace>', cell("process", "", ref="process")),
             cells(cell("thread-state", "2", fmt="Waiting"), cell("weight", "9000000", fmt="9.00 ms"), '<tagged-backtrace fmt="wait"><backtrace/></tagged-backtrace>', cell("process", "", ref="process")),
             cells(cell("thread-state", "1", fmt="Running"), cell("weight", "8000000", fmt="8.00 ms"), '<tagged-backtrace fmt="other"><backtrace/></tagged-backtrace>', '<process fmt="Other (8)"><pid>8</pid></process>')]))
        write(capture / "device-thermal-state-intervals.xml", query(
            "device-thermal-state-intervals", ["start", "duration", "thermal-state"],
            [cells(cell("start-time", "0", fmt="00:00.000.000"), cell("duration", "10000000000", fmt="10.00 s"), cell("thermal-state", "0", fmt="Nominal")), cells(cell("start-time", "10000000000", fmt="00:10.000.000"), cell("duration", "20000000000", fmt="20.00 s"), cell("thermal-state", "1", fmt="Fair"))]))
        output = root / "analysis"
        command = ["python3", str(ANALYZER), "--input", str(capture), "--output", str(output), "--presentation-metric", "Presentation interval", "--cpu-metric", "CPU frame", "--gpu-metric", "GPU frame", "--hitch-reference-hz", "120"]
        result = subprocess.run(command, capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        report = json.loads((output / "report.json").read_text())
        assert report["provenance"]["template"] == "Game Performance Overview"
        assert report["schema_inventory"]["unknown_preserved_but_not_interpreted"] == ["future-schema"]
        assert not report["schema_inventory"]["status"]["metal-perf-overview-layer-duration-metric"]["available"]
        cadence = report["measurements"]["cadence"]
        assert cadence["sample_count"] == 4 and cadence["p50_ms"] == 8.333333 and cadence["cadence_clusters"]["120"] == 2 and cadence["cadence_clusters"]["60"] == 1
        assert cadence["cadence_runs"] == [{"classification": "120", "sample_count": 2}, {"classification": "60", "sample_count": 1}, {"classification": "30", "sample_count": 1}]
        candidates = cadence["multi_interval_hitch_candidates"]
        assert candidates["count"] == 2 and candidates["candidate_only"]
        catalog = report["metric_catalog"]
        assert len(catalog) == 4 and all(entry["name"] != "Other" for entry in catalog)
        cpu_catalog = next(entry for entry in catalog if entry["label"] == "CPU frame")
        assert cpu_catalog["value_column"] == "metric-value" and cpu_catalog["observed_cell_tags"] == ["duration"]
        assert any(entry["label"] == "unspecified" and entry["observed_cell_tags"] == ["fixed-decimal"] for entry in catalog)
        assert report["measurements"]["cpu_frame_metric"]["p95_ms"] == 4.0
        assert report["measurements"]["gpu_frame_metric"]["sample_count"] == 1
        assert report["measurements"]["sampled_cpu"]["running_weight_ms"] == 2.0
        assert report["measurements"]["sampled_cpu"]["running_occupancy_percent_of_capture"] == 0.006667
        assert report["measurements"]["thermal"]["intervals"][1]["state"] == "Fair"
        assert (output / "report.csv").read_text().startswith("category,available")
        deterministic = root / "deterministic"
        result = subprocess.run(command[:command.index("--output") + 1] + [str(deterministic)] + command[command.index("--output") + 2:], capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        assert (output / "report.json").read_text() == (deterministic / "report.json").read_text()
        assert (output / "report.csv").read_text() == (deterministic / "report.csv").read_text()
        missing = root / "missing"
        result = subprocess.run(["python3", str(ANALYZER), "--input", str(capture), "--output", str(missing), "--presentation-metric", "unknown"], capture_output=True, text=True)
        assert result.returncode == 0
        report = json.loads((missing / "report.json").read_text())
        assert not report["measurements"]["cadence"]["available"]
        assert not report["measurements"]["gpu_frame_metric"]["available"]
        units = root / "units"
        result = subprocess.run(["python3", str(ANALYZER), "--input", str(capture), "--output", str(units), "--gpu-metric", "unspecified"], capture_output=True, text=True)
        assert result.returncode == 2 and "unsupported metric-value unit/tag fixed-decimal" in result.stderr
        no_cpu_xml = root / "no-cpu.xml"
        write(no_cpu_xml, query("time-profile", ["thread-state", "weight", "stack", "process"], []))
        no_cpu = root / "no-cpu"
        result = subprocess.run(["python3", str(ANALYZER), "--input", str(capture), "--output", str(no_cpu), "--xml", f"time-profile={no_cpu_xml}"], capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        report = json.loads((no_cpu / "report.json").read_text())
        assert not report["measurements"]["sampled_cpu"]["available"]
        bad = root / "bad"
        write(root / "wrong.xml", query("wrong-schema", ["a"], [cells(cell("a", "1"))]))
        result = subprocess.run(["python3", str(ANALYZER), "--input", str(capture), "--output", str(bad), "--xml", f"time-profile={root / 'wrong.xml'}"], capture_output=True, text=True)
        assert result.returncode == 2 and "schema mismatch" in result.stderr
    print("ios-game-performance-analysis-check: PASS")


if __name__ == "__main__":
    main()
