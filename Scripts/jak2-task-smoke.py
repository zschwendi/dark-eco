#!/usr/bin/env python3
"""Validate one simulator Jak II task launch: resolved task, live target, and stable submissions.

Exit codes: 0 PASS, 1 FAIL, 2 usage error, 3 PENDING (poll mode only; final mode never pends).
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import math
import os
import re
import sys
import tempfile
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path


def load_scene_checker():
    path = Path(__file__).with_name("jak2-scene-sweep.py")
    spec = importlib.util.spec_from_file_location("jak2_scene_sweep", path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"jak2-task-smoke: cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module  # dataclasses resolve their module through sys.modules
    previous = sys.dont_write_bytecode
    try:
        sys.dont_write_bytecode = True
        spec.loader.exec_module(module)
    finally:
        sys.dont_write_bytecode = previous
    return module


scene = load_scene_checker()
SmokeFailure = scene.SweepFailure

EXIT_PASS, EXIT_FAIL, EXIT_USAGE, EXIT_PENDING = 0, 1, 2, 3
NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,62}")  # GOAL_JAK2_DEBUG_PLAY_TASK_NAME_MAX = 63
TIMESTAMP = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d(?:\.\d+)?)")
RUNTIME_FIELDS = re.compile(r"\bmode=(\S*) title=(\S*) scene=(\S*) target=(\S*)")
# Both level lists are empty before the first title DGO finishes loading.
LEVELS = re.compile(r"\bdesired=(\S*)\s+active=(\S*)(?=\s|$)")
ALIVE = re.compile(r"\bsmoke-target=([01])/([01])\b")
DRAWABLES = re.compile(r"\bdrawable=(\d+)/(\d+)\b")
STREAM_CLOCK = re.compile(r"GOALPAD_JAK2_STREAM_CLOCK_STATE tick=(\d+) pulls=(\d+)/(\d+)")
# These process-state names are never playable, even when the checked target is not dead.
DEAD_TARGET = re.compile(r"title|death|dead|dying|\bdie\b|^#f$|^none$", re.IGNORECASE)
RUNTIME_ERRORS = (
    ("DGO failures", re.compile(r"\bresult=-?\d+ failures=(\d+)\b")),
    ("malformed DMA chains", re.compile(r"\bdma=\d+/\d+/(\d+)\b")),
    ("progress missing-texture draws", re.compile(r"\bprogress=\d+/\d+/\d+/(\d+)\b")),
)
HOST_ERROR = re.compile(r"\berror=(.*?)(?=\s+smoke-target=\d+/\d+(?:\s|$)|$)")
MAX_LOG_BYTES = 64 * 1024 * 1024
PRESENTATION_EVIDENCE = (
    "unavailable on simulator: addPresentedHandler is excluded; zero callback drops do not prove "
    "absence of dropped frames; no physical display proof"
)
LIMITATIONS = (
    PRESENTATION_EVIDENCE,
    "screenshots are central non-black capture triage only; they prove neither rendering, audio, nor mission completion",
    "STREAM_CLOCK pulls are counters only, not audible-output proof",
    "stdout markers carry no PID or timestamp; they are bound to this launch only by its per-process --stdout file",
)


# ---- Play-task marker contract -----------------------------------------------------------------
# Success: the authored GOAL helper resolved and spawned the exact task.
#   GOAL (progress.gc):  [pc-debug-play-task] result=spawned task="NAME" index=N continue="CONT" spawn=target
# Failure: result=error, a verb of error/rejected/failed, or any error= field.
# Informational only, never success: queued, request, blocked-save-menu.
PLAY_MARKER = re.compile(
    r"(?:\[GOALPAD_JAK2_DEBUG_PLAY_TASK\]|\[pc-debug-play-task\]|GOALPAD_JAK2_DEBUG_PLAY_TASK)\s+(.*)$"
)
TOKEN = re.compile(r'([A-Za-z][\w-]*)=("(?:[^"\\]|\\.)*"|\S*)|(\S+)')


@dataclass(frozen=True)
class PlayMarker:
    kind: str  # started | error | info
    verb: str
    fields: dict


def parse_play_marker(line: str) -> PlayMarker | None:
    match = PLAY_MARKER.search(line)
    if not match:
        return None
    fields: dict[str, str] = {}
    verbs: list[str] = []
    for key, value, bare in TOKEN.findall(match.group(1)):
        if key:
            fields[key] = value[1:-1] if len(value) >= 2 and value[0] == value[-1] == '"' else value
        else:
            verbs.append(bare)
    verb = fields.get("result") or (verbs[0] if verbs else "")
    if verb in ("error", "rejected", "failed") or "error" in fields:
        return PlayMarker("error", verb, fields)
    if verb == "spawned" and "[pc-debug-play-task]" in line:
        valid = (
            fields.get("task")
            and re.fullmatch(r"\d+", fields.get("index", ""))
            and fields.get("continue")
            and fields.get("spawn") == "target"
        )
        return PlayMarker("started" if valid else "error", verb, fields)
    return PlayMarker("info", verb, fields)


# ---- Telemetry ------------------------------------------------------------------------------------
@dataclass(frozen=True)
class Runtime:
    ts: float
    tick: int
    mode: str
    target: str
    target_valid: int | None
    alive: int | None
    active: frozenset
    chains: int
    commands: int
    drawables_acquired: int
    drawables_submitted: int
    presentation_callbacks: int


@dataclass
class Verdict:
    status: str = "PASS"
    failures: list = field(default_factory=list)  # [category, reason]
    pending: str = ""
    info: dict = field(default_factory=dict)

    def fail(self, category: str, reason: str) -> None:
        self.status = "FAIL"
        self.failures.append([category, reason])


def parse_timestamp(line: str) -> float | None:
    match = TIMESTAMP.match(line)
    if not match:
        return None
    text = match.group(1)
    try:
        return datetime.strptime(text, "%Y-%m-%d %H:%M:%S.%f" if "." in text else "%Y-%m-%d %H:%M:%S").timestamp()
    except ValueError as error:
        raise SmokeFailure(f"invalid runtime timestamp: {text}") from error


def parse_runtime(line: str) -> tuple[Runtime, list[str]]:
    tick, ts = scene.parse_tick(line), parse_timestamp(line)
    fields, levels = RUNTIME_FIELDS.search(line), LEVELS.search(line)
    counters = [pattern.search(line) for pattern in (scene.CHAIN, scene.COMMAND, scene.SUBMIT)]
    drawables = DRAWABLES.search(line)
    extras = [pattern.search(line) for _, pattern in RUNTIME_ERRORS]
    host_error = HOST_ERROR.search(line)
    if tick is None or not fields or not levels or not all(counters) or not drawables or not all(extras) or not host_error:
        scene.fail(f"malformed runtime telemetry: {line[:160]}")
    if ts is None:
        scene.fail(f"runtime telemetry at tick {tick} has no verifiable unified-log timestamp")
    errors = [
        f"{label} errors={match.group(3)} at tick {tick}"
        for label, match in zip(("chain", "command", "presentation-drop"), counters)
        if int(match.group(3))
    ]
    errors += [
        f"{label}={match.group(1)} at tick {tick}"
        for (label, _), match in zip(RUNTIME_ERRORS, extras)
        if int(match.group(1))
    ]
    if host_error.group(1).strip():
        errors.append(f"Metal host error at tick {tick}: {host_error.group(1).strip()[:120]}")
    alive = ALIVE.search(line)
    runtime = Runtime(
        ts, tick, fields.group(1), fields.group(4),
        int(alive.group(1)) if alive else None, int(alive.group(2)) if alive else None,
        frozenset(level for level in levels.group(2).split("+") if level),
        int(counters[0].group(2)), int(counters[1].group(2)), int(drawables.group(1)),
        int(counters[2].group(1)), int(counters[2].group(2)),
    )
    return runtime, errors


def family_errors(line: str) -> list[str]:
    tick = scene.parse_tick(line)
    errors: list[str] = []
    if scene.STACK_MARKER in line:
        match = scene.STACK.search(line)
        if not match:
            scene.fail("stack telemetry omitted overflow/failure counters")
        if int(match.group(1)) or int(match.group(2)):
            errors.append(f"stack overflows/failures={match.group(1)}/{match.group(2)} at tick {tick}")
    elif scene.FOREGROUND_MARKER in line:
        for label, pattern in scene.FOREGROUND_ERRORS:
            match = pattern.search(line)
            if not match:
                scene.fail(f"foreground telemetry omitted {label}")
            if int(match.group(1)):
                errors.append(f"{label}={match.group(1)} at tick {tick}")
    elif scene.RENDERER_MARKER in line:
        r = scene.parse_renderer_observation(line)
        for label, value in (
            ("ocean command-buffer errors", r.ocean_command_buffer_errors),
            ("ocean missing textures", r.ocean_missing_textures),
            ("background missing textures", r.background_missing_textures),
            ("background unexpected DMA", r.background_unexpected_dma),
        ):
            if value:
                errors.append(f"{label}={value} at tick {r.tick}")
    return errors


def unhealthy_reason(o: Runtime, level: str) -> str | None:
    if o.mode != "game":
        return f"mode={o.mode or '<empty>'} at tick {o.tick}"
    if level not in o.active:
        return f"expected level {level} not active at tick {o.tick} (active={'+'.join(sorted(o.active)) or '<none>'})"
    if o.target_valid != 1 or o.alive != 1:
        return f"checked smoke-target={o.target_valid}/{o.alive} at tick {o.tick}; require 1/1"
    # Release builds may omit the legacy state name; the checked snapshot owns liveness.
    if DEAD_TARGET.search(o.target):
        return f"target state {o.target or '<none>'} is not a living target at tick {o.tick}"
    return None


def stable_window(observations: list[Runtime], level: str) -> tuple[list[Runtime], str]:
    run: list[Runtime] = []
    reset = "no runtime telemetry from the launched PID"
    for o in observations:
        why = unhealthy_reason(o, level)
        if why:
            run, reset = [], why
            continue
        if run:
            p = run[-1]
            stalled = [
                name for name, before, after in (
                    ("ticks", p.tick, o.tick), ("chains", p.chains, o.chains),
                    ("commands", p.commands, o.commands),
                    ("acquired drawables", p.drawables_acquired, o.drawables_acquired),
                    ("submitted drawables", p.drawables_submitted, o.drawables_submitted),
                ) if after <= before
            ]
            if stalled or o.ts < p.ts:
                run, reset = [], f"frozen {'/'.join(stalled) or 'timestamps'} at tick {o.tick}"
        run.append(o)
    return run, reset


def evaluate(task: str, level: str, pid: int, dwell: float,
             log_lines: list[str], stdout_lines: list[str], final: bool) -> Verdict:
    v = Verdict(info={"task": task, "expected_level": level, "pid": pid, "dwell_seconds": dwell,
                      "presentation_callback_evidence": PRESENTATION_EVIDENCE})
    own = scene.filter_process(log_lines, pid)
    v.info["foreign_pid_lines"] = len(log_lines) - len(own)
    markers = [m for line in own + stdout_lines if (m := parse_play_marker(line))]
    started = [m for m in markers if m.kind == "started"]
    for m in markers:
        if m.kind == "error":
            v.fail("telemetry-failure", f"play-task error marker: {m.verb} {m.fields}")
        elif m.kind == "started" and m.fields["task"] != task:
            v.fail("telemetry-failure", f"wrong task resolved: {m.fields['task']} (requested {task})")
    if started:
        v.info["resolved"] = {k: started[-1].fields.get(k) for k in ("task", "index", "continue")}

    observations: list[Runtime] = []
    families = {scene.STACK_MARKER: [], scene.FOREGROUND_MARKER: [], scene.RENDERER_MARKER: []}
    pulls: list[tuple[int, int]] = []
    try:
        for line in own:
            if scene.RUNTIME_MARKER in line:
                runtime, errors = parse_runtime(line)
                observations.append(runtime)
            else:
                errors = family_errors(line)
                for marker, ticks in families.items():
                    if marker in line:
                        ticks.append(scene.parse_tick(line))
                if (clock := STREAM_CLOCK.search(line)):
                    pulls.append((int(clock.group(2)), int(clock.group(3))))
            for error in errors:
                v.fail("telemetry-failure", f"hard error: {error}")
    except SmokeFailure as error:
        v.fail("telemetry-failure", str(error))
    if pulls:
        v.info["stream_pulls"] = {"first": pulls[0], "last": pulls[-1], "note": LIMITATIONS[1]}

    run, reset = stable_window(observations, level)
    if run:
        v.info["window"] = {"first_tick": run[0].tick, "last_tick": run[-1].tick, "observations": len(run),
                            "seconds": round(run[-1].ts - run[0].ts, 3), "target": run[-1].target}
        v.info["drawable_counters"] = {
            "acquired": [run[0].drawables_acquired, run[-1].drawables_acquired],
            "submitted": [run[0].drawables_submitted, run[-1].drawables_submitted],
            "presentation_callbacks": [run[0].presentation_callbacks, run[-1].presentation_callbacks],
        }
        missing = [
            marker for marker, ticks in families.items()
            if not any(t is not None and run[0].tick <= t <= run[-1].tick for t in ticks)
        ]
    else:
        missing = []
    for line in own if v.status != "FAIL" else []:
        if (run and scene.RENDERER_MARKER in line
                and run[0].tick <= (scene.parse_tick(line) or -1) <= run[-1].tick):
            renderer = scene.parse_renderer_observation(line)
            if renderer.background_missing_levels:
                v.fail("telemetry-failure", f"missing level geometry at tick {renderer.tick}")
            if renderer.ocean_command_buffers_completed > renderer.ocean_command_buffers_committed:
                v.fail("telemetry-failure", f"ocean completions exceed submissions at tick {renderer.tick}")
            if renderer.eyes_composed and not renderer.eyes_active:
                v.fail("telemetry-failure", f"invalid eye vertex-stream contract at tick {renderer.tick}")
    if v.status == "FAIL":
        return v
    if not started:
        queued = any(m.kind == "info" and m.verb == "queued" for m in markers)
        v.pending = "only a queued marker was observed (queued is not success)" if queued else "no explicit started/spawned play-task marker"
    elif len(run) < 3 or run[-1].ts - run[0].ts < dwell:
        seconds = run[-1].ts - run[0].ts if run else 0.0
        v.pending = f"stable window {len(run)} observations/{seconds:.1f}s < 3/{dwell:g}s; last reset: {reset}"
    elif missing:
        v.pending = f"stable window lacks {', '.join(missing)} telemetry"
    if v.pending:
        v.status = "PENDING"
        if final:
            v.fail("telemetry-failure", v.pending)
    return v


def window_ms(v: Verdict) -> int:
    window = v.info.get("window")
    return int(window["seconds"] * 1000) if window else 0


def check_screenshots(paths: list[Path], report: Path) -> None:
    if (len(paths) != 3 or len({p.resolve() for p in paths}) != 3
            or any(not p.is_file() or p.stat().st_size == 0 for p in paths)):
        scene.fail(f"expected exactly 3 non-empty screenshots, found {sum(p.is_file() for p in paths)}")
    _, samples = scene.select_visual_samples(paths, report)
    blank = [s.path.name for s in samples if not s.content_bearing]
    if blank:
        scene.fail(f"black/blank screenshot(s): {', '.join(blank)}; see {report}")


def read_lines(path: Path | None, final: bool = False) -> list[str]:
    if path is None or not path.exists():
        return []
    if path.stat().st_size > MAX_LOG_BYTES:
        scene.fail(f"log exceeds {MAX_LOG_BYTES} bytes: {path}")
    text = path.read_text(errors="replace")
    if text and not text.endswith("\n"):
        if final:
            scene.fail(f"log ends with an incomplete line: {path}")
        text = text.rpartition("\n")[0]
    return text.splitlines()


# ---- CLI helpers -----------------------------------------------------------------------------------
def parse_pairs(pairs: list[str]) -> list[tuple[str, str]]:
    parsed: list[tuple[str, str]] = []
    for pair in pairs:
        task, sep, level = pair.partition("=")
        if not sep or not NAME.fullmatch(task) or not NAME.fullmatch(level):
            scene.fail(f"invalid TASK=EXPECTED_LEVEL pair {pair!r}")
        if any(task == seen for seen, _ in parsed):
            scene.fail(f"duplicate task {task!r}")
        parsed.append((task, level))
    if not parsed:
        scene.fail("at least one TASK=EXPECTED_LEVEL pair is required")
    return parsed


def prepare_artifacts(path: Path) -> None:
    if path.exists() or path.is_symlink():
        scene.fail(f"artifacts directory already exists; use a new directory: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    os.mkdir(path)  # exclusive: fails if another run created it first


def summarize(artifacts: Path) -> int:
    tasks_file = artifacts / "tasks.tsv"
    rows, failed = [], 0
    pairs = [line.split("\t") for line in tasks_file.read_text().splitlines()] if tasks_file.is_file() else []
    for task, level in pairs:
        try:
            result = json.loads((artifacts / task / "result.json").read_text())
        except (OSError, ValueError):
            result = {"status": "FAIL", "category": "missing-result", "reason": "result.json absent or invalid"}
        failed += result.get("status") != "PASS"
        rows.append({"task": task, "expected_level": level, **{k: result.get(k, "") for k in ("status", "category", "reason")}})
    (artifacts / "summary.json").write_text(json.dumps({"tasks": rows, "failed": failed,
        "presentation_callback_evidence": PRESENTATION_EVIDENCE}, indent=2) + "\n")
    with (artifacts / "summary.tsv").open("w") as out:
        out.write("task\texpected_level\tstatus\tcategory\treason\n")
        for row in rows:
            out.write("\t".join(str(row[k]).replace("\t", " ") for k in ("task", "expected_level", "status", "category", "reason")) + "\n")
    return EXIT_FAIL if failed or not rows else EXIT_PASS


def finalize(args) -> int:
    lines, stdout = [], []
    v = Verdict()
    try:
        lines, stdout = read_lines(args.log, final=True), read_lines(args.stdout_log, final=True)
    except SmokeFailure as error:
        v.fail("telemetry-failure", str(error))
    if args.pid is not None:
        evaluated = evaluate(args.task, args.level, args.pid, args.dwell, lines, stdout, final=True)
        v.info, v.failures = evaluated.info, v.failures + evaluated.failures
    else:
        v.fail("launch-error", "no launch PID")
    if args.runner_failure:
        category, _, reason = args.runner_failure.partition(":")
        v.failures.insert(0, [category, reason])
    for check, category in (
        (lambda: scene.compare_saves(args.save_before, args.save_after), "changed-save"),
        (lambda: check_screenshots(args.screenshot, args.visual_report), "screenshot-failure"),
    ):
        try:
            check()
        except (SmokeFailure, OSError) as error:
            v.failures.append([category, str(error)])
    v.status = "FAIL" if v.failures else "PASS"
    result = {"status": v.status, "category": v.failures[0][0] if v.failures else "",
              "reason": v.failures[0][1] if v.failures else "", "failures": v.failures,
              **v.info, "limitations": list(LIMITATIONS)}
    args.result.write_text(json.dumps(result, indent=2, default=str) + "\n")
    print(f"{v.status} {args.task}: {result['category']} {result['reason']}".rstrip())
    return EXIT_PASS if v.status == "PASS" else EXIT_FAIL


# ---- Self-test -------------------------------------------------------------------------------------
FOREGROUND_OK = (
    "merc=1/1/1 malformed=0 reject-reason=0 missing-models=0 merc-anim=0/0 merc-eyes=0/0/0/0 "
    "merc-missing-textures=0 bones=0/0/0/0 generic=0/0/0 missing-textures=0 unexpected-dma=0 "
    "eyes=0/0/0 missing=0 unexpected=0 duplicate=0 eye-cmd=0/0/0 sprite-placeholder=0/0"
)


def synth(pid=1234, n=4, step=5.0, level="alpha", target="target-stance", freeze=None, extra=""):
    base, out = datetime(2026, 11, 14, 10, 0, 0), []
    for i in range(n):
        stamp = (base + timedelta(seconds=i * step)).strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
        prefix = f"{stamp} Df GOALPad[{pid}:1a2b] "
        tick = 1000 + i * 600 if freeze != "tick" else 1000
        count = 100 + i * 50 if freeze != "submissions" else 100
        drawables = 100 + i * 50 if freeze != "drawables" else 100
        commands = 100 + i * 50 if freeze != "commands" else 100
        chains = 100 + i * 50
        out += [
            f"{prefix}GOALPAD_JAK2_RUNTIME_STATE tick={tick} mode=game title=idle scene=none target={target} "
            f"pmode=1.000 desired={level} active={level}+ctyport dgo=x/y result=0 failures=0 dma=5/5/0 "
            f"bytes=1/1 chains={chains}/{chains}/0 cmd={chains}/{commands}/0 cmd-last=4/0 drawable={drawables}/0 "
            f"submit={count}/0/0 draws=1/1 progress=0/0/0/0 map=0/0/0 buckets=1 skipped=0 error={extra} smoke-target=1/1",
            f"{prefix}GOALPAD_JAK2_STACK_STATE tick={tick} suspends=0 current=1/2 deepest=1/2 fullest=1/2 overflows=0 failures=0",
            f"{prefix}GOALPAD_JAK2_FOREGROUND_STATE tick={tick} {FOREGROUND_OK}",
            f"{prefix}GOALPAD_JAK2_RENDERER_STATE tick={tick} ocean=0/0/0/0/0 missing=0 cmd=0/0/0 phase=0/0 "
            f"transfers=0/0 grammar=0/0 calls=0/0 tfrag=3/6 tie=2/4 background-missing=0/0 unexpected=0 "
            f"eye=0/0/0 vertex-stream=0/0/0/0x0000000000000000",
            f"{prefix}GOALPAD_JAK2_STREAM_CLOCK_STATE tick={tick} pulls={i}/{i * 512}",
        ]
    return out


STARTED = ['[pc-debug-play-task] result=spawned task="sample-task" index=7 continue="ctyport-start" spawn=target']


def self_test() -> None:
    def status(log, stdout=STARTED, final=True, pid=1234, level="alpha"):
        return evaluate("sample-task", level, pid, 10.0, log, stdout, final)

    good = synth()
    assert status(good).status == "PASS", status(good).failures
    assert status(good).info["drawable_counters"]["presentation_callbacks"] == [0, 0]
    assert "unavailable on simulator" in status(good).info["presentation_callback_evidence"]
    startup = (
        "2026-11-15 00:01:38.758 Df Dark Eco[1234:c3dd86] (GOALPadJak2Runtime) "
        "GOALPAD_JAK2_RUNTIME_STATE tick=1 mode=game title= scene= target= pmode=0.000 "
        "desired= active= dgo=/TITLE.DGO result=0 failures=0 dma=0/0/0 bytes=0/0 "
        "chains=1/1/0 cmd=1/0/0 cmd-last=0/0 drawable=1/0 submit=1/0/0 draws=0/0 "
        "progress=0/0/0/0 map=1/1/1 buckets=327 skipped=0 error= smoke-target=0/0"
    )
    initial, errors = parse_runtime(startup)
    assert not initial.active and initial.target == "" and not errors
    assert status([startup], stdout=[], final=False).status == "PENDING"
    assert status([startup], final=False).status == "PENDING"
    assert status([startup] + good).status == "PASS"
    assert status([startup.replace("cmd=1/0/0", "cmd=1/0/1")] + good).status == "FAIL"
    release_row = (
        "2026-11-15 00:09:31.136 Df Dark Eco[1234:c414ca] (GOALPadJak2Runtime) "
        "GOALPAD_JAK2_RUNTIME_STATE tick=8520 mode=game title=idle scene= target= pmode=1.000 "
        "desired=prison+forexita active=prison dgo=/FEA.DGO result=0 failures=0 dma=0/0/0 "
        "bytes=0/0 chains=8520/8520/0 cmd=8520/8519/0 cmd-last=4/0 drawable=8489/0 "
        "submit=8489/0/0 draws=527/136166 progress=0/0/0/0 map=13742/1/1 buckets=327 "
        "skipped=159625872 error= smoke-target=1/1"
    )
    released, errors = parse_runtime(release_row)
    assert not errors and unhealthy_reason(released, "prison") is None
    for flag in ("0/0", "1/0"):
        invalid, _ = parse_runtime(release_row.replace("smoke-target=1/1", f"smoke-target={flag}"))
        assert unhealthy_reason(invalid, "prison") is not None
    empty_state = synth(target="")
    assert status(empty_state).status == "PASS"
    assert status(empty_state, stdout=[]).status == "FAIL"
    assert status(empty_state, level="prison").status == "FAIL"
    for flag in ("0/0", "1/0"):
        assert status([l.replace("smoke-target=1/1", f"smoke-target={flag}") for l in empty_state]).status == "FAIL"
    native = ["2026-11-14 10:00:00.000 Df GOALPad[1234:1] [GOALPAD_JAK2_DEBUG_PLAY_TASK] started task=sample-task index=7 continue=ctyport-start"]
    assert status(good + native, stdout=[]).status == "FAIL"  # unsupported native start is not GOAL spawn proof
    queued = ["GOALPAD_JAK2_DEBUG_PLAY_TASK queued task=sample-task"]
    assert status(good, stdout=queued, final=False).status == "PENDING"
    assert "queued" in status(good, stdout=queued).failures[0][1]
    cases = {
        "wrong task": (good, [STARTED[0].replace('"sample-task"', '"other-task"')]),
        "error marker": (good, ['[pc-debug-play-task] result=error task="sample-task" error=unknown-task']),
        "started without continue": (good, ["[GOALPAD_JAK2_DEBUG_PLAY_TASK] started task=sample-task index=7"]),
        "wrong level": (synth(level="beta"), STARTED),
        "target dead": (synth(target="target-death"), STARTED),
        "target title": (synth(target="target-title"), STARTED),
        "target dead bit": ([l.replace("smoke-target=1/1", "smoke-target=1/0") for l in good], STARTED),
        "invalid target": ([l.replace("smoke-target=1/1", "smoke-target=0/0") for l in good], STARTED),
        "missing checked target": ([l.replace(" smoke-target=1/1", "") for l in good], STARTED),
        "frozen ticks": (synth(freeze="tick"), STARTED),
        "frozen submitted drawables": (synth(freeze="submissions"), STARTED),
        "frozen acquired drawables": (synth(freeze="drawables"), STARTED),
        "frozen completed commands": (synth(freeze="commands"), STARTED),
        "presentation drops": ([l.replace("submit=100/0/0", "submit=100/0/1") for l in good], STARTED),
        "missing drawable counters": ([l.replace("drawable=", "drawable-missing=") for l in good], STARTED),
        "insufficient dwell": (synth(step=2.0), STARTED),
        "too few observations": (synth(n=2, step=12.0), STARTED),
        "malformed runtime": ([l.replace(" chains=", " chainz=") for l in good], STARTED),
        "missing telemetry": ([], STARTED),
        "no timestamps": ([l.split(" ", 3)[3] for l in good], STARTED),
        "hard error after pass": (good + synth(n=1, extra="metal-device-lost")[:1], STARTED),
        "stack overflow": (good + [good[1].replace("overflows=0", "overflows=1")], STARTED),
        "missing texture": (good + [good[2].replace("merc-missing-textures=0", "merc-missing-textures=2")], STARTED),
        "missing level geometry": ([l.replace("background-missing=0/0", "background-missing=1/0") for l in good], STARTED),
        "wrong PID": (synth(pid=999), STARTED),
    }
    for name, (log, stdout) in cases.items():
        verdict = status(log, stdout)
        assert verdict.status == "FAIL", f"self-test accepted {name}: {verdict.info}"
    assert status(synth(step=2.0), final=False).status == "PENDING"
    assert status([], stdout=[], final=False).status == "PENDING"
    assert status([l.replace(" error= smoke-target=1/1", " smoke-target=1/1 error=") for l in good]).status == "PASS"

    for bad in (["../x=alpha"], ["a/b=c"], ["task="], ["=lvl"], ["t=l/../x"], ["t=a", "t=b"], [], ["x" * 64 + "=l"]):
        try:
            parse_pairs(bad)
        except SmokeFailure:
            continue
        raise AssertionError(f"self-test accepted pairs {bad}")
    assert parse_pairs(["city-help-kid=ctysluma"]) == [("city-help-kid", "ctysluma")]

    with tempfile.TemporaryDirectory() as directory:
        tmp = Path(directory)
        saves = tmp / "saves"
        saves.mkdir()
        (saves / "bank0.bin").write_bytes(b"save")
        before, after = tmp / "before.tsv", tmp / "after.tsv"
        scene.snapshot_saves(saves, before)
        (saves / "bank0.bin").write_bytes(b"SAVE")
        scene.snapshot_saves(saves, after)
        try:
            scene.compare_saves(before, after)
        except SmokeFailure:
            pass
        else:
            raise AssertionError("self-test accepted a mutated save hash")
        black = [tmp / f"black-{i}.png" for i in range(3)]
        for path in black:
            scene.write_test_png(path, 20, 20, bytes(20 * 20 * 3))
        lit = [tmp / f"lit-{i}.png" for i in range(3)]
        for path in lit:
            scene.write_test_png(path, 20, 20, b"\x40\x60\x80" * 400)
        check_screenshots(lit, tmp / "visual.tsv")
        for shots in (black, [*lit[:2], black[0]], lit[:2], [*lit[:2], tmp / "absent.png"], [lit[0]] * 3):
            try:
                check_screenshots(shots, tmp / "visual.tsv")
            except SmokeFailure:
                continue
            raise AssertionError(f"self-test accepted screenshots {shots}")
        artifacts = tmp / "run"
        prepare_artifacts(artifacts)
        try:
            prepare_artifacts(artifacts)
        except SmokeFailure:
            pass
        else:
            raise AssertionError("self-test reused an artifacts directory")
        (artifacts / "tasks.tsv").write_text("sample-task\talpha\n")
        assert summarize(artifacts) == EXIT_FAIL  # result.json missing
        (artifacts / "sample-task").mkdir()
        (artifacts / "sample-task" / "result.json").write_text('{"status": "PASS"}')
        assert summarize(artifacts) == EXIT_PASS
    print("jak2-task-smoke: self-test PASS")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--self-test", action="store_true")
    mode.add_argument("--validate-pairs", nargs="*", metavar="TASK=LEVEL")
    mode.add_argument("--prepare-artifacts", type=Path)
    mode.add_argument("--snapshot-saves", type=Path)
    mode.add_argument("--poll", action="store_true", help="print status, window ms, observations, reason")
    mode.add_argument("--final", action="store_true", help="write result.json for one task")
    mode.add_argument("--summarize", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--task")
    parser.add_argument("--level")
    parser.add_argument("--pid", type=int)
    parser.add_argument("--dwell", type=float, default=10.0)
    parser.add_argument("--log", type=Path)
    parser.add_argument("--stdout-log", type=Path)
    parser.add_argument("--save-before", type=Path)
    parser.add_argument("--save-after", type=Path)
    parser.add_argument("--screenshot", action="append", type=Path, default=[])
    parser.add_argument("--visual-report", type=Path)
    parser.add_argument("--runner-failure", default="")
    parser.add_argument("--result", type=Path)
    args = parser.parse_args()
    try:
        if args.self_test:
            self_test()
            return EXIT_PASS
        if args.validate_pairs is not None:
            for task, level in parse_pairs(args.validate_pairs):
                print(f"{task}\t{level}")
            return EXIT_PASS
        if args.prepare_artifacts:
            prepare_artifacts(args.prepare_artifacts)
            return EXIT_PASS
        if args.snapshot_saves:
            if not args.output:
                parser.error("--snapshot-saves requires --output")
            if args.snapshot_saves.is_symlink():
                scene.fail(f"save root is a symlink: {args.snapshot_saves}")
            scene.snapshot_saves(args.snapshot_saves, args.output)
            return EXIT_PASS
        if args.summarize:
            return summarize(args.summarize)
        if not args.task or not args.level or not math.isfinite(args.dwell) or args.dwell <= 0:
            parser.error("--task, --level, and a positive --dwell are required")
        if args.poll:
            if args.pid is None or not args.log:
                parser.error("--poll requires --pid and --log")
            v = evaluate(args.task, args.level, args.pid, args.dwell,
                         read_lines(args.log), read_lines(args.stdout_log), final=False)
            window = v.info.get("window", {})
            reason = v.failures[0][1] if v.failures else v.pending
            print(f"{v.status}\t{window_ms(v)}\t{window.get('observations', 0)}\t{reason}")
            return {"PASS": EXIT_PASS, "PENDING": EXIT_PENDING}.get(v.status, EXIT_FAIL)
        if not (args.result and args.save_before and args.save_after and args.visual_report):
            parser.error("--final requires --result, --save-before, --save-after, and --visual-report")
        return finalize(args)
    except SmokeFailure as error:
        print(f"jak2-task-smoke: FAIL: {error}", file=sys.stderr)
        return EXIT_USAGE if args.validate_pairs is not None or args.prepare_artifacts else EXIT_FAIL


if __name__ == "__main__":
    raise SystemExit(main())
