#!/usr/bin/env python3
"""Validate one Jak II scene-preview telemetry capture without scene-specific oracles."""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


RUNTIME_MARKER = "GOALPAD_JAK2_RUNTIME_STATE"
SCENE_MARKER = "GOALPAD_JAK2_SCENE_STATE"
STACK_MARKER = "GOALPAD_JAK2_STACK_STATE"
TICK = re.compile(r"\btick=(\d+)\b")
SCENE = re.compile(r"\bscene=(\d+)/(\d+)\b.*\bidentity=([^ ]*)")
ANIMATION = re.compile(r"\banim=1/[^/]+/[-+0-9.eE]+/([-+0-9.eE]+)")
CHAIN = re.compile(r"\bchains=(\d+)/(\d+)/(\d+)\b")
COMMAND = re.compile(r"\bcmd=(\d+)/(\d+)/(\d+)\b")
SUBMIT = re.compile(r"\bsubmit=(\d+)/(\d+)/(\d+)\b")
STACK = re.compile(r"\boverflows=(\d+)\s+failures=(\d+)\b")
LEVELS = re.compile(r"\bdesired=([^ ]*)\s+active=([^ ]*)\b")
PID = re.compile(r"\[(\d+):")


class SweepFailure(RuntimeError):
    pass


@dataclass(frozen=True)
class SceneObservation:
    tick: int
    aframe: float | None


def fail(message: str) -> None:
    raise SweepFailure(message)


def parse_tick(line: str) -> int | None:
    match = TICK.search(line)
    return int(match.group(1)) if match else None


def filter_process(lines: list[str], pid: int | None) -> list[str]:
    if pid is None:
        return lines
    return [line for line in lines if (match := PID.search(line)) and int(match.group(1)) == pid]


def required_levels_for_scene(requirements: list[str], scene: str) -> set[str]:
    levels: set[str] = set()
    for requirement in requirements:
        try:
            requested_scene, level = requirement.split("=", 1)
        except ValueError as error:
            raise SweepFailure(
                f"invalid --required-level {requirement!r}; expected scene=level"
            ) from error
        if not requested_scene or not level:
            fail(f"invalid --required-level {requirement!r}; expected scene=level")
        if requested_scene == scene:
            levels.add(level)
    return levels


def collect_scene_observations(lines: list[str], scene: str) -> tuple[list[SceneObservation], int | None]:
    observations: list[SceneObservation] = []
    completed_tick: int | None = None
    for line in lines:
        if SCENE_MARKER not in line:
            continue
        tick = parse_tick(line)
        match = SCENE.search(line)
        if tick is None or not match:
            continue
        scene_active = int(match.group(1)) != 0
        identity = match.group(3).split("|")
        if scene_active and len(identity) == 3 and all(identity) and identity[2] == scene:
            animation = ANIMATION.search(line)
            observations.append(
                SceneObservation(tick, float(animation.group(1)) if animation else None)
            )
        if observations and tick > observations[-1].tick and match.group(1) == "0" and match.group(2) == "0" and match.group(3) == "||":
            completed_tick = tick
            break
    return observations, completed_tick


def validate(lines: list[str], scene: str, requirements: list[str]) -> str:
    observations, completed_tick = collect_scene_observations(lines, scene)
    if not observations:
        fail(f"{scene}: no matching non-empty scene identity was observed")
    if completed_tick is None:
        fail(f"{scene}: no no-save scene completion (scene=0/0 identity=||) was observed")

    aframes = [observation.aframe for observation in observations if observation.aframe is not None]
    if len(aframes) < 2 or max(aframes) - min(aframes) <= 0.001:
        fail(f"{scene}: animation aframe did not advance while the scene identity was active")

    first_tick = observations[0].tick
    scoped = [line for line in lines if (tick := parse_tick(line)) is not None and first_tick <= tick <= completed_tick]
    runtime_lines = [line for line in scoped if RUNTIME_MARKER in line]
    stack_lines = [line for line in scoped if STACK_MARKER in line]
    if not runtime_lines:
        fail(f"{scene}: no runtime telemetry was captured between identity and completion")
    if not stack_lines:
        fail(f"{scene}: no stack telemetry was captured between identity and completion")

    for line in runtime_lines:
        for label, pattern in (("chain", CHAIN), ("command", COMMAND), ("submit", SUBMIT)):
            match = pattern.search(line)
            if not match:
                fail(f"{scene}: runtime telemetry omitted {label} counters")
            if int(match.group(3)) != 0:
                fail(f"{scene}: {label} errors were nonzero at tick {parse_tick(line)}")
    for line in stack_lines:
        match = STACK.search(line)
        if not match:
            fail(f"{scene}: stack telemetry omitted overflow/failure counters")
        if int(match.group(1)) != 0 or int(match.group(2)) != 0:
            fail(f"{scene}: stack errors were nonzero at tick {parse_tick(line)}")

    expected_levels = required_levels_for_scene(requirements, scene)
    observed_levels: set[str] = set()
    observation_ticks = {observation.tick for observation in observations}
    for line in runtime_lines:
        if parse_tick(line) not in observation_ticks:
            continue
        match = LEVELS.search(line)
        if match:
            observed_levels.update(level for group in match.groups() for level in group.split("+") if level)
    missing_levels = expected_levels - observed_levels
    if missing_levels:
        fail(
            f"{scene}: required levels were not observed as a subset: {', '.join(sorted(missing_levels))}; "
            f"observed {', '.join(sorted(observed_levels)) or '<none>'}"
        )

    return (
        f"PASS {scene}: identity ticks {first_tick}-{observations[-1].tick}; "
        f"aframe {min(aframes):.3f}->{max(aframes):.3f}; completion tick {completed_tick}; "
        f"required levels subset {','.join(sorted(expected_levels)) or '<none>'}"
    )


def snapshot_saves(root: Path, output: Path) -> None:
    records: list[str] = []
    if root.exists():
        if not root.is_dir():
            fail(f"save root is not a directory: {root}")
        for path in sorted(root.rglob("*")):
            if path.is_symlink():
                fail(f"save snapshot rejects symlink: {path}")
            if path.is_file():
                stat = path.stat()
                digest = hashlib.sha256(path.read_bytes()).hexdigest()
                records.append(f"{path.relative_to(root)}\t{stat.st_size}\t{stat.st_mtime_ns}\t{digest}\n")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("".join(records))


def compare_saves(before: Path, after: Path) -> None:
    if before.read_bytes() != after.read_bytes():
        fail(f"save manifests differ: {before} != {after}")


def self_test() -> None:
    scene = "sample-scene"
    good_log = "\n".join(
        (
            "GOALPAD_JAK2_RUNTIME_STATE tick=100 mode=game desired=alpha+beta active=alpha+beta chains=10/10/0 cmd=10/10/0 submit=10/10/0",
            "GOALPAD_JAK2_SCENE_STATE tick=100 scene=1/1 identity=entity|group|sample-scene anim=1/00000000/1.000/10.000",
            "GOALPAD_JAK2_STACK_STATE tick=100 overflows=0 failures=0",
            "GOALPAD_JAK2_RUNTIME_STATE tick=200 mode=game desired=alpha+beta active=alpha+beta chains=20/20/0 cmd=20/20/0 submit=20/20/0",
            "GOALPAD_JAK2_SCENE_STATE tick=200 scene=1/1 identity=entity|group|sample-scene anim=1/00000000/2.000/20.000",
            "GOALPAD_JAK2_STACK_STATE tick=200 overflows=0 failures=0",
            "GOALPAD_JAK2_RUNTIME_STATE tick=300 mode=progress desired=alpha+beta active=alpha+beta chains=30/30/0 cmd=30/30/0 submit=30/30/0",
            "GOALPAD_JAK2_SCENE_STATE tick=300 scene=0/0 identity=|| anim=0/00000000/0.000/0.000",
            "GOALPAD_JAK2_STACK_STATE tick=300 overflows=0 failures=0",
        )
    )
    assert validate(good_log.splitlines(), scene, ["sample-scene=alpha"]).startswith("PASS")
    try:
        validate(good_log.replace("submit=20/20/0", "submit=20/20/1").splitlines(), scene, [])
    except SweepFailure:
        pass
    else:
        raise AssertionError("self-test accepted a submit error")
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory) / "saves"
        root.mkdir()
        (root / "bank0").write_bytes(b"save")
        before = Path(directory) / "before.tsv"
        after = Path(directory) / "after.tsv"
        snapshot_saves(root, before)
        snapshot_saves(root, after)
        compare_saves(before, after)
    print("jak2-scene-sweep: self-test PASS")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scene")
    parser.add_argument("--log", type=Path)
    parser.add_argument("--pid", type=int)
    parser.add_argument("--required-level", action="append", default=[])
    parser.add_argument("--screenshot", action="append", type=Path, default=[])
    parser.add_argument("--save-before", type=Path)
    parser.add_argument("--save-after", type=Path)
    parser.add_argument("--snapshot-saves", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--compare-saves", action="store_true")
    parser.add_argument("--event", choices=("observed", "completed"))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            self_test()
            return 0
        if args.snapshot_saves:
            if not args.output:
                parser.error("--snapshot-saves requires --output")
            snapshot_saves(args.snapshot_saves, args.output)
            return 0
        if args.compare_saves:
            if not args.save_before or not args.save_after:
                parser.error("--compare-saves requires --save-before and --save-after")
            compare_saves(args.save_before, args.save_after)
            return 0
        if not args.scene or not args.log:
            parser.error("--scene and --log are required for telemetry validation")
        lines = filter_process(args.log.read_text(errors="replace").splitlines(), args.pid)
        observations, completion = collect_scene_observations(lines, args.scene)
        if args.event == "observed":
            return 0 if observations else 1
        if args.event == "completed":
            return 0 if completion is not None else 1
        if not args.save_before or not args.save_after:
            parser.error("telemetry validation requires --save-before and --save-after")
        if not args.screenshot or any(not screenshot.is_file() or screenshot.stat().st_size == 0 for screenshot in args.screenshot):
            fail("telemetry validation requires non-empty screenshot artifacts")
        compare_saves(args.save_before, args.save_after)
        print(validate(lines, args.scene, args.required_level))
        return 0
    except SweepFailure as error:
        print(f"jak2-scene-sweep: FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
