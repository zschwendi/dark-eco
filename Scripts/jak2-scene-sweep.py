#!/usr/bin/env python3
"""Validate one Jak II scene-preview telemetry capture without scene-specific oracles."""

from __future__ import annotations

import argparse
import hashlib
import re
import struct
import sys
import tempfile
import zlib
from dataclasses import dataclass
from pathlib import Path


RUNTIME_MARKER = "GOALPAD_JAK2_RUNTIME_STATE"
SCENE_MARKER = "GOALPAD_JAK2_SCENE_STATE"
STACK_MARKER = "GOALPAD_JAK2_STACK_STATE"
FOREGROUND_MARKER = "GOALPAD_JAK2_FOREGROUND_STATE"
TICK = re.compile(r"\btick=(\d+)\b")
SCENE = re.compile(r"\bscene=(\d+)/(\d+)\b.*\bidentity=([^ ]*)")
ANIMATION = re.compile(r"\banim=1/[^/]+/[-+0-9.eE]+/([-+0-9.eE]+)")
CHAIN = re.compile(r"\bchains=(\d+)/(\d+)/(\d+)\b")
COMMAND = re.compile(r"\bcmd=(\d+)/(\d+)/(\d+)\b")
SUBMIT = re.compile(r"\bsubmit=(\d+)/(\d+)/(\d+)\b")
STACK = re.compile(r"\boverflows=(\d+)\s+failures=(\d+)\b")
LEVELS = re.compile(r"\bdesired=([^ ]*)\s+active=([^ ]*)\b")
PID = re.compile(r"\[(\d+):")
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
MAX_PNG_BYTES = 16 * 1024 * 1024
MAX_PNG_PIXELS = 4_000_000
CONTENT_CHANNEL_THRESHOLD = 20
CONTENT_FRACTION_THRESHOLD = 0.005
FOREGROUND_ERRORS = (
    ("malformed Merc DMA", re.compile(r"\bmalformed=(\d+)\b")),
    ("Merc preflight rejection", re.compile(r"\breject-reason=(\d+)\b")),
    ("missing Merc models", re.compile(r"\bmissing-models=(\d+)\b")),
    ("Merc animated-slot placeholders", re.compile(r"\bmerc-anim=\d+/(\d+)\b")),
    ("Merc eye renderer misses", re.compile(r"\bmerc-eyes=\d+/(\d+)/\d+/\d+\b")),
    ("Merc eye lookup failures", re.compile(r"\bmerc-eyes=\d+/\d+/(\d+)/\d+\b")),
    ("Merc eye placeholders", re.compile(r"\bmerc-eyes=\d+/\d+/\d+/(\d+)\b")),
    ("missing Merc textures", re.compile(r"\bmerc-missing-textures=(\d+)\b")),
    ("bad Merc bone pointers", re.compile(r"\bbones=(\d+)/\d+/\d+/\d+\b")),
    ("missing Merc bone slots", re.compile(r"\bbones=\d+/(\d+)/\d+/\d+\b")),
    ("nonfinite Merc bones", re.compile(r"\bbones=\d+/\d+/(\d+)/\d+\b")),
    ("degenerate Merc bones", re.compile(r"\bbones=\d+/\d+/\d+/(\d+)\b")),
    ("missing Generic2 textures", re.compile(r"\bgeneric=\d+/\d+/\d+ missing-textures=(\d+)\b")),
    ("unexpected Generic2 DMA", re.compile(r"\bunexpected-dma=(\d+)\b")),
    ("missing eye textures", re.compile(r"\beyes=\d+/\d+/\d+ missing=(\d+)\b")),
    ("unexpected eye DMA", re.compile(r"\beyes=\d+/\d+/\d+ missing=\d+ unexpected=(\d+)\b")),
    ("duplicate eye writes", re.compile(r"\bduplicate=(\d+)\b")),
    ("eye command-buffer errors", re.compile(r"\beye-cmd=\d+/\d+/(\d+)\b")),
    ("Sprite3 placeholder batches", re.compile(r"\bsprite-placeholder=(\d+)/\d+\b")),
    ("Sprite3 placeholder sprites", re.compile(r"\bsprite-placeholder=\d+/(\d+)\b")),
)


class SweepFailure(RuntimeError):
    pass


@dataclass(frozen=True)
class SceneObservation:
    tick: int
    aframe: float | None


@dataclass(frozen=True)
class VisualSample:
    path: Path
    width: int
    height: int
    central_pixels: int
    non_black_pixels: int

    @property
    def non_black_fraction(self) -> float:
        return self.non_black_pixels / self.central_pixels

    @property
    def content_bearing(self) -> bool:
        return self.non_black_fraction >= CONTENT_FRACTION_THRESHOLD


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


def next_sample_observation(
    observations: list[SceneObservation], after_tick: int, minimum_tick_gap: int
) -> SceneObservation | None:
    if not observations:
        return None
    latest = observations[-1]
    return latest if after_tick == 0 or latest.tick >= after_tick + minimum_tick_gap else None


def unfilter_png_rows(raw: bytes, width: int, height: int, channels: int) -> bytes:
    row_bytes = width * channels
    expected_size = height * (row_bytes + 1)
    if len(raw) != expected_size:
        fail(f"PNG scanline size mismatch: expected {expected_size}, got {len(raw)}")
    rows = bytearray(height * row_bytes)
    previous = bytearray(row_bytes)
    offset = 0
    for row_index in range(height):
        filter_type = raw[offset]
        offset += 1
        encoded = raw[offset : offset + row_bytes]
        offset += row_bytes
        row_start = row_index * row_bytes
        row = rows[row_start : row_start + row_bytes]
        for index, value in enumerate(encoded):
            left = row[index - channels] if index >= channels else 0
            above = previous[index]
            upper_left = previous[index - channels] if index >= channels else 0
            if filter_type == 0:
                decoded = value
            elif filter_type == 1:
                decoded = value + left
            elif filter_type == 2:
                decoded = value + above
            elif filter_type == 3:
                decoded = value + ((left + above) // 2)
            elif filter_type == 4:
                pa = abs(above - upper_left)
                pb = abs(left - upper_left)
                pc = abs(left + above - (upper_left * 2))
                predictor = left if pa <= pb and pa <= pc else above if pb <= pc else upper_left
                decoded = value + predictor
            else:
                fail(f"unsupported PNG filter type: {filter_type}")
            row[index] = decoded & 0xFF
        rows[row_start : row_start + row_bytes] = row
        previous = row
    return bytes(rows)


def decode_png(path: Path) -> tuple[int, int, int, bytes]:
    payload = path.read_bytes()
    if len(payload) > MAX_PNG_BYTES:
        fail(f"visual sample exceeds {MAX_PNG_BYTES} bytes: {path}")
    if not payload.startswith(PNG_SIGNATURE):
        fail(f"visual sample is not a PNG: {path}")

    offset = len(PNG_SIGNATURE)
    header: tuple[int, int, int, int, int] | None = None
    compressed = bytearray()
    while offset < len(payload):
        if offset + 12 > len(payload):
            fail(f"truncated PNG chunk: {path}")
        length = struct.unpack(">I", payload[offset : offset + 4])[0]
        chunk_type = payload[offset + 4 : offset + 8]
        chunk_end = offset + 12 + length
        if chunk_end > len(payload):
            fail(f"truncated PNG payload: {path}")
        chunk = payload[offset + 8 : offset + 8 + length]
        offset = chunk_end
        if chunk_type == b"IHDR":
            if header is not None or len(chunk) != 13:
                fail(f"invalid PNG header: {path}")
            width, height, bit_depth, color_type, compression, filter_method, interlace = struct.unpack(
                ">IIBBBBB", chunk
            )
            if not width or not height or width * height > MAX_PNG_PIXELS:
                fail(f"visual sample dimensions are out of bounds: {path}")
            if bit_depth != 8 or color_type not in (0, 2, 4, 6) or compression or filter_method or interlace:
                fail(f"unsupported PNG format: {path}")
            header = width, height, color_type, bit_depth, interlace
        elif chunk_type == b"IDAT":
            compressed.extend(chunk)
        elif chunk_type == b"IEND":
            break
    if header is None or not compressed:
        fail(f"incomplete PNG visual sample: {path}")
    width, height, color_type, _, _ = header
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[color_type]
    try:
        raw = zlib.decompress(compressed)
    except zlib.error as error:
        raise SweepFailure(f"invalid PNG image data: {path}") from error
    return width, height, color_type, unfilter_png_rows(raw, width, height, channels)


def inspect_visual_sample(path: Path) -> VisualSample:
    width, height, color_type, pixels = decode_png(path)
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[color_type]
    x_start, x_end = width // 10, width - (width // 10)
    y_start, y_end = height * 15 // 100, height - (height * 15 // 100)
    central_pixels = 0
    non_black_pixels = 0
    for y in range(y_start, y_end):
        row_start = y * width * channels
        for x in range(x_start, x_end):
            index = row_start + x * channels
            if color_type in (0, 4):
                red = green = blue = pixels[index]
            else:
                red, green, blue = pixels[index : index + 3]
            alpha = pixels[index + channels - 1] if color_type in (4, 6) else 255
            central_pixels += 1
            if alpha and max(red, green, blue) >= CONTENT_CHANNEL_THRESHOLD:
                non_black_pixels += 1
    return VisualSample(path, width, height, central_pixels, non_black_pixels)


def select_visual_samples(paths: list[Path], report: Path) -> tuple[VisualSample, list[VisualSample]]:
    if not paths:
        fail("visual selection requires active-scene screenshot samples")
    samples = [inspect_visual_sample(path) for path in paths]
    content_bearing = [sample for sample in samples if sample.content_bearing]
    report.parent.mkdir(parents=True, exist_ok=True)
    lines = ["sample\twidth\theight\tcentral_pixels\tnon_black_pixels\tnon_black_fraction\tcontent_bearing\n"]
    for sample in samples:
        lines.append(
            f"{sample.path.name}\t{sample.width}\t{sample.height}\t{sample.central_pixels}\t"
            f"{sample.non_black_pixels}\t{sample.non_black_fraction:.6f}\t{int(sample.content_bearing)}\n"
        )
    if content_bearing:
        selected = max(content_bearing, key=lambda sample: sample.non_black_fraction)
        lines.append(
            f"selected\t{selected.path.name}\tcentral_non_black_fraction={selected.non_black_fraction:.6f}\n"
        )
    else:
        lines.append("selected\t<none>\tno central non-black sample\n")
    lines.append(
        "note\tcentral-crop non-black selection is a capture triage signal, not renderer or gameplay correctness proof\n"
    )
    report.write_text("".join(lines))
    if not content_bearing:
        fail(f"no content-bearing active-scene screenshot sample; see {report}")
    return selected, samples


def read_visual_sample_list(path: Path) -> list[Path]:
    try:
        entries = path.read_text().splitlines()
    except OSError as error:
        raise SweepFailure(f"could not read visual sample list: {path}") from error
    samples = [Path(entry) for entry in entries if entry]
    if not samples:
        fail(f"visual sample list is empty: {path}")
    return samples


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
    foreground_lines = [line for line in scoped if FOREGROUND_MARKER in line]
    if not runtime_lines:
        fail(f"{scene}: no runtime telemetry was captured between identity and completion")
    if not stack_lines:
        fail(f"{scene}: no stack telemetry was captured between identity and completion")
    if not foreground_lines:
        fail(f"{scene}: no foreground telemetry was captured between identity and completion")

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
    for line in foreground_lines:
        for label, pattern in FOREGROUND_ERRORS:
            match = pattern.search(line)
            if not match:
                fail(f"{scene}: foreground telemetry omitted {label}")
            if int(match.group(1)) != 0:
                fail(f"{scene}: {label} were nonzero at tick {parse_tick(line)}")

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


def write_test_png(path: Path, width: int, height: int, pixels: bytes) -> None:
    if len(pixels) != width * height * 3:
        raise AssertionError("test PNG pixel count mismatch")

    def chunk(chunk_type: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + chunk_type
            + payload
            + struct.pack(">I", zlib.crc32(chunk_type + payload) & 0xFFFFFFFF)
        )

    scanlines = b"".join(
        b"\0" + pixels[row * width * 3 : (row + 1) * width * 3] for row in range(height)
    )
    path.write_bytes(
        PNG_SIGNATURE
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(scanlines))
        + chunk(b"IEND", b"")
    )


def self_test() -> None:
    scene = "sample-scene"
    good_log = "\n".join(
        (
            "GOALPAD_JAK2_RUNTIME_STATE tick=100 mode=game desired=alpha+beta active=alpha+beta chains=10/10/0 cmd=10/10/0 submit=10/10/0",
            "GOALPAD_JAK2_SCENE_STATE tick=100 scene=1/1 identity=entity|group|sample-scene anim=1/00000000/1.000/10.000",
            "GOALPAD_JAK2_STACK_STATE tick=100 overflows=0 failures=0",
            "GOALPAD_JAK2_FOREGROUND_STATE tick=100 merc=1/1/1 malformed=0 reject-reason=0 missing-models=0 merc-anim=0/0 merc-eyes=0/0/0/0 merc-missing-textures=0 bones=0/0/0/0 generic=0/0/0 missing-textures=0 unexpected-dma=0 eyes=0/0/0 missing=0 unexpected=0 duplicate=0 eye-cmd=0/0/0 sprite-placeholder=0/0",
            "GOALPAD_JAK2_RUNTIME_STATE tick=200 mode=game desired=alpha+beta active=alpha+beta chains=20/20/0 cmd=20/20/0 submit=20/20/0",
            "GOALPAD_JAK2_SCENE_STATE tick=200 scene=1/1 identity=entity|group|sample-scene anim=1/00000000/2.000/20.000",
            "GOALPAD_JAK2_STACK_STATE tick=200 overflows=0 failures=0",
            "GOALPAD_JAK2_FOREGROUND_STATE tick=200 merc=1/1/1 malformed=0 reject-reason=0 missing-models=0 merc-anim=1/0 merc-eyes=1/0/0/0 merc-missing-textures=0 bones=0/0/0/0 generic=1/1/1 missing-textures=0 unexpected-dma=0 eyes=1/1/1 missing=0 unexpected=0 duplicate=0 eye-cmd=1/1/0 sprite-placeholder=0/0",
            "GOALPAD_JAK2_RUNTIME_STATE tick=300 mode=progress desired=alpha+beta active=alpha+beta chains=30/30/0 cmd=30/30/0 submit=30/30/0",
            "GOALPAD_JAK2_SCENE_STATE tick=300 scene=0/0 identity=|| anim=0/00000000/0.000/0.000",
            "GOALPAD_JAK2_STACK_STATE tick=300 overflows=0 failures=0",
            "GOALPAD_JAK2_FOREGROUND_STATE tick=300 merc=0/0/0 malformed=0 reject-reason=0 missing-models=0 merc-anim=0/0 merc-eyes=0/0/0/0 merc-missing-textures=0 bones=0/0/0/0 generic=0/0/0 missing-textures=0 unexpected-dma=0 eyes=0/0/0 missing=0 unexpected=0 duplicate=0 eye-cmd=0/0/0 sprite-placeholder=0/0",
        )
    )
    assert validate(good_log.splitlines(), scene, ["sample-scene=alpha"]).startswith("PASS")
    observations, _ = collect_scene_observations(good_log.splitlines(), scene)
    assert next_sample_observation(observations, 0, 1) == observations[1]
    assert next_sample_observation(observations, observations[0].tick, 1) == observations[1]
    assert next_sample_observation(observations, observations[1].tick, 1) is None
    try:
        validate(good_log.replace("submit=20/20/0", "submit=20/20/1").splitlines(), scene, [])
    except SweepFailure:
        pass
    else:
        raise AssertionError("self-test accepted a submit error")
    try:
        validate(good_log.replace("merc-missing-textures=0", "merc-missing-textures=1", 1).splitlines(), scene, [])
    except SweepFailure:
        pass
    else:
        raise AssertionError("self-test accepted a missing Merc texture")
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory) / "saves"
        root.mkdir()
        (root / "bank0").write_bytes(b"save")
        before = Path(directory) / "before.tsv"
        after = Path(directory) / "after.tsv"
        snapshot_saves(root, before)
        snapshot_saves(root, after)
        compare_saves(before, after)
        black = Path(directory) / "black.png"
        content = Path(directory) / "content.png"
        report = Path(directory) / "visual-samples.tsv"
        write_test_png(black, 20, 20, bytes(20 * 20 * 3))
        content_pixels = bytearray(20 * 20 * 3)
        for y in range(5, 15):
            for x in range(5, 15):
                content_pixels[(y * 20 + x) * 3 : (y * 20 + x + 1) * 3] = b"\x30\x50\x70"
        write_test_png(content, 20, 20, bytes(content_pixels))
        selected, samples = select_visual_samples([black, content], report)
        assert selected.path == content
        assert len(samples) == 2 and not samples[0].content_bearing and samples[1].content_bearing
        assert "selected\tcontent.png" in report.read_text()
        current_samples = Path(directory) / "current-visual-samples.txt"
        current_samples.write_text(f"{content}\n")
        assert read_visual_sample_list(current_samples) == [content]
        selected, samples = select_visual_samples(read_visual_sample_list(current_samples), report)
        assert selected.path == content and len(samples) == 1
        try:
            select_visual_samples([black], report)
        except SweepFailure:
            pass
        else:
            raise AssertionError("self-test accepted an all-black visual sample set")
    print("jak2-scene-sweep: self-test PASS")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scene")
    parser.add_argument("--log", type=Path)
    parser.add_argument("--pid", type=int)
    parser.add_argument("--required-level", action="append", default=[])
    parser.add_argument("--screenshot", action="append", type=Path, default=[])
    parser.add_argument("--visual-sample", action="append", type=Path, default=[])
    parser.add_argument("--visual-sample-list", type=Path)
    parser.add_argument("--visual-report", type=Path)
    parser.add_argument("--save-before", type=Path)
    parser.add_argument("--save-after", type=Path)
    parser.add_argument("--snapshot-saves", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--compare-saves", action="store_true")
    parser.add_argument("--event", choices=("observed", "completed", "sample"))
    parser.add_argument("--sample-after-tick", type=int, default=0)
    parser.add_argument("--sample-minimum-ticks", type=int, default=1)
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
        if args.event == "sample":
            if args.sample_after_tick < 0 or args.sample_minimum_ticks < 1:
                parser.error("sample tick arguments must be non-negative and positive respectively")
            observation = next_sample_observation(
                observations, args.sample_after_tick, args.sample_minimum_ticks
            )
            if observation is None:
                return 1
            aframe = "<none>" if observation.aframe is None else f"{observation.aframe:.3f}"
            print(f"{observation.tick}\t{aframe}")
            return 0
        if not args.save_before or not args.save_after:
            parser.error("telemetry validation requires --save-before and --save-after")
        if args.visual_sample and args.visual_sample_list:
            parser.error("use either --visual-sample or --visual-sample-list, not both")
        visual_samples = (
            read_visual_sample_list(args.visual_sample_list)
            if args.visual_sample_list
            else args.visual_sample
        )
        screenshot_artifacts = args.screenshot + visual_samples
        if not screenshot_artifacts or any(
            not screenshot.is_file() or screenshot.stat().st_size == 0
            for screenshot in screenshot_artifacts
        ):
            fail("telemetry validation requires non-empty screenshot artifacts")
        if not visual_samples or not args.visual_report:
            fail("telemetry validation requires active-scene visual samples and a visual report path")
        compare_saves(args.save_before, args.save_after)
        selected, _ = select_visual_samples(visual_samples, args.visual_report)
        print(validate(lines, args.scene, args.required_level))
        print(
            f"VISUAL {args.scene}: selected {selected.path.name}; "
            f"central non-black {selected.non_black_fraction:.3%}; "
            "capture triage only, not renderer correctness proof"
        )
        return 0
    except SweepFailure as error:
        print(f"jak2-scene-sweep: FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
