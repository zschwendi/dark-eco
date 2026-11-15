#!/usr/bin/env python3
"""ASan-check the actual emitted race-manager update method without game assets.

Pass an existing race_manager.c; this script never regenerates or rewrites it.
The extracted method, its referenced static bytes, and the production C runtime
helpers are unchanged. Synthetic state disables optional debug drawing and ends
the test at a counting race-state update stub; it does not exercise that callee.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


FUNCTION = "goal_race_manager__method_update_race_manager_"


def harness(source: str, source_path: Path) -> tuple[str, dict]:
    signature = f"uint64_t {FUNCTION}(uint64_t a0) {{"
    start = source.index(signature)
    end = source.index("\n}\n", start) + 3
    method = source[start:end]
    stack_sizes = re.findall(r"uint8_t goal_stack\[(\d+)\]", method)
    if len(stack_sizes) != 1:
        raise ValueError("Expected exactly one emitted stack allocation")
    symbols_match = re.search(
        r"static const char\* const goalc_symbol_names\[\d+\] = \{(.*?)\};",
        source, re.S,
    )
    if not symbols_match:
        raise ValueError("Missing emitted symbol table")
    symbols = re.findall(r'"([^"\\]*)"', symbols_match.group(1))
    debug_slot = symbols.index("*display-race-marks*")
    state_slot = symbols.index("race-state")
    static_indices = sorted(set(map(int, re.findall(
        r'goal_static_addr\("race_manager", (\d+)\)', method))))
    declarations = []
    cases = []
    for index in static_indices:
        match = re.search(
            rf"static const uint8_t goalc_static_{index}_data\[\d+\] = \{{[^}}]*\}};",
            source,
        )
        if not match or f"goalc_static_{index}_relocs[]" in source:
            raise ValueError(f"Unsupported static data/relocations for {index}")
        declarations.append(match.group())
        cases.append(f"case {index}: return GOAL_ADDR_OF(goalc_static_{index}_data);")
    line = source[:start].count("\n") + 1
    prefix = f'''#include "goalc/aot/goal_c_runtime.h"
#include <assert.h>
static uint8_t memory[4096] __attribute__((aligned(16)));
uint8_t* g_goal_mem = memory;
uint64_t g_goal_mem_size = sizeof(memory);
uint64_t g_goal_mem_low_protect = 16;
uint64_t g_goal_s7 = 64;
uint64_t g_goal_current_process = 256;
static int32_t symbol_values[{len(symbols)}];
static int32_t* goalc_symbol_slots[{len(symbols)}];
static int update_calls;
static uint64_t finish_update(uint64_t state) {{
  assert(state == 512);
  ++update_calls;
  return 0;
}}
{chr(10).join(declarations)}
uint64_t goal_static_addr(const char* file, int index) {{
  assert(strcmp(file, "race_manager") == 0);
  switch (index) {{
    {chr(10).join(cases)}
    default: abort();
  }}
}}
#line {line} {json.dumps(str(source_path))}
'''
    suffix = f'''
#line 1 "synthetic-race-state-fixture.c"
int main(void) {{
  for (int i = 0; i < {len(symbols)}; ++i) goalc_symbol_slots[i] = &symbol_values[i];
  symbol_values[{debug_slot}] = 0;
  symbol_values[{state_slot}] = 1024;
  goal_store(memory + 256 + 124, 512, 4);
  goal_store(memory + 512, 768, 4);
  goal_store(memory + 1024 + 60, 1280, 4);
  void* entry = (void*)&finish_update;
  memcpy(memory + 1280, &entry, sizeof(entry));
  goal_vf sphere = {{1, 2, 3, 4}};
  goal_vf direction = {{0, 0, 1, 0}};
  goal_store_vf(memory + 768 + 28, sphere);
  goal_store_vf(memory + 768 + 44, direction);
  assert({FUNCTION}(256) == 0);
  assert(update_calls == 1);
  puts("race-manager emitted update completed; downstream update called once");
  return 0;
}}
'''
    return prefix + method + suffix, {
        "function": FUNCTION,
        "method_sha256": hashlib.sha256(method.encode()).hexdigest(),
        "stack_bytes": int(stack_sizes[0]),
        "method_line": line,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generated", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--expect", choices=("overflow", "clean"), required=True)
    parser.add_argument("--opengoal", type=Path,
                        default=Path(__file__).resolve().parents[1] / "OpenGOAL")
    args = parser.parse_args()
    generated = args.generated.resolve()
    raw = generated.read_bytes()
    code, result = harness(raw.decode(), generated)
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    harness_path = output / "race-manager-emitted-harness.c"
    executable = output / "race-manager-emitted-harness"
    harness_path.write_text(code)
    compiler = shutil.which("clang")
    if not compiler:
        raise RuntimeError("clang is required")
    command = [compiler, "-std=c11", "-O0", "-g", "-fsanitize=address",
               "-fno-omit-frame-pointer", "-I", str(args.opengoal.resolve()),
               str(harness_path), "-o", str(executable)]
    compiled = subprocess.run(command, capture_output=True, text=True, timeout=60)
    (output / "compile.log").write_text(compiled.stdout + compiled.stderr)
    result.update(generated=str(generated), generated_sha256=hashlib.sha256(raw).hexdigest(),
                  expected=args.expect, compile_command=command,
                  compile_returncode=compiled.returncode)
    passed = False
    if compiled.returncode == 0:
        env = dict(os.environ, ASAN_OPTIONS="detect_leaks=0:halt_on_error=1:abort_on_error=0")
        run = subprocess.run([str(executable)], capture_output=True, text=True,
                             env=env, timeout=30)
        log = run.stdout + run.stderr
        (output / "run.log").write_text(log)
        first_error = next((line for line in log.splitlines()
                            if "ERROR: AddressSanitizer:" in line), None)
        result.update(run_returncode=run.returncode, first_asan_error=first_error)
        if args.expect == "overflow":
            passed = (result["stack_bytes"] == 80 and run.returncode != 0
                      and "ERROR: AddressSanitizer: stack-buffer-overflow" in log
                      and "WRITE of size 16" in log and "goal_stack" in log)
        else:
            passed = (result["stack_bytes"] == 96 and run.returncode == 0
                      and "AddressSanitizer" not in log
                      and "downstream update called once" in log)
    result["passed"] = passed
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
