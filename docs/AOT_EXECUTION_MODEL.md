# AOT execution model for iPadOS

Status: **Implemented**, with the limits recorded at the end of this file.

Real Jak 1 GOAL code, compiled by the AOT C backend, executes inside the real
OpenGOAL kernel on ARM64 with no writable-executable memory anywhere. Verified
on the ARM64 macOS host and the iPad Pro 11-inch (M5) simulator, and link plus
code-sign verified for `arm64-apple-ios`. See `game/kernel/core/aot_loader.*`
and `game/kernel/core/aot_execution_test.cpp` in the OpenGOAL fork.

This document originally recorded the analysis that had to be settled before
further compiler work. That analysis held up, and the approach it recommended
is the one that shipped.

## The single blocking mechanism

Desktop OpenGOAL executes GOAL code out of the GOAL heap.

- `game/runtime.cpp:160-170` maps `g_ee_main_mem` with
  `PROT_EXEC | PROT_READ | PROT_WRITE` at a fixed address.
- `game/kernel/jak1/klink.cpp:216-229` copies each object file's main code
  segment into that heap with `kmalloc` and `ultimate_memcpy`, then executes it
  in place.
- `game/mips2c/mips2c_table.cpp:663-703` allocates a `0x40`-byte GOAL heap
  object and writes raw x86 machine code into it as a trampoline to a native
  C++ function.

All three require writable-executable memory. Ordinary iPadOS provides none of
them, and the project may not depend on JIT entitlements or jailbreak
behavior.

Everything else the linker does is data relocation into the GOAL heap, which is
legal on iPadOS. `common/link_types.h:11-16` defines only four relocation
kinds: `LINK_TABLE_END`, `LINK_SYMBOL_OFFSET`, `LINK_TYPE_PTR`, and
`LINK_PTR`. None of them requires generating code.

**Consequence: the AOT problem is narrower than previously assumed.** Static
data, symbols, types, and object loading can keep using the real upstream
linker at runtime. Only the code segment must be replaced.

## What a GOAL function actually is

A GOAL function is an ordinary heap object of type `function` whose address is
a 32-bit offset from `g_ee_main_mem`. Calls jump to `g_ee_main_mem + offset`.
The mips2c path already proves that a *natively compiled C/C++ function* can
stand in for a GOAL function against the real runtime — it just reaches it
through a runtime-generated trampoline.

So the AOT question reduces to: **how does a call site reach native code in the
signed app image using a 32-bit GOAL offset, without generating any code at
runtime?**

## Candidate approaches

### A. Place the app's `__TEXT` inside the `g_ee_main_mem` window — REJECTED, measured

GOAL offsets are unsigned 32-bit, giving a 4 GiB window above the base, while
`EE_MAIN_MEM_SIZE` is only 128 MiB (`common/goal_constants.h:109`). If
`g_ee_main_mem` were mapped at a base chosen so the app's `__TEXT` fell within
4 GiB *above* it, an AOT function's GOAL address would simply be
`(native_fn_addr - g_ee_main_mem)` and every existing call site would work
unchanged with zero runtime code generation and no per-call cost.

This was tested directly on the macOS ARM64 host and **does not work**:

- arm64 reserves the entire low 4 GiB, so the base must be at or above
  `0x100000000`.
- The main executable's `__TEXT` consistently lands only **40–77 MiB** above
  that floor across ASLR runs — never the 128 MiB of headroom a GOAL heap
  placed below it would require.
- Enlarging `__PAGEZERO` does not help; the linker caps it at 4 GB
  (`ld: warning: -pagezero_size is too large, setting it to 4GB`) and `__TEXT`
  still landed 77 MiB above the floor.
- Putting the AOT code in a dylib does not help either. dyld places the dylib
  immediately adjacent to the main image — measured separation was under
  150 KiB across runs — so there is no configuration where app code sits far
  enough above a mappable heap base.

Mapping the heap *above* all app code fails by construction, because the offset
would be negative and GOAL offsets are unsigned.

Note that a build which drops the debug heap needs only about 64 MiB rather
than 128 MiB, which would sometimes fit. That is a coincidence of ASLR
placement, not a guarantee, and must not be relied on.

### B. Function objects carry a native pointer — ADOPTED, implemented

The AOT compiler generates the static data for function objects as well as the
code, and GOALPad controls every call site: the AOT backend emits GOAL-to-GOAL
calls, and `call_goal` in the runtime is ours. So the 32-bit address slot can
instead hold a tagged index into an AOT function table built at link time, or
the function object can carry a full 64-bit native pointer.

This has no address-range constraint at all, which is exactly why it should be
preferred over A. Costs one indirection on the call path. The risks to check
are GOAL source that treats a function pointer as an integer, and the
`method-set!` / type-method-table paths, where function addresses are stored in
heap data whose layout the compiler also emits.

## Where AOT code comes from

The AOT C backend (`goalc/aot/CBackend.cpp`, `goalc/aot/goal_c_runtime.h`) emits
C from the GOAL IR and compiles it with clang for arm64, which supplies a
complete optimizing backend, normal Mach-O objects, and ordinary code signing.
Current whole-game coverage is **10,596 emitted C functions plus 7 declared
native routines** across all 518 Jak 1 sources, with zero source or function
coverage failures. All generated translations compile for ARM64 Apple targets.
The native set covers the register, stack, thread, and exception operations
that must not be lowered to ordinary C arithmetic; four earlier exceptions were
rewritten as plain GOAL with equivalent behavior.

The stack model is settled and documented in the fork's `docs/aot-stack-model.md`:
**GOAL runs on stacks inside GOAL memory, as upstream does.** gkernel requires
it — `reset-and-call` sets SP to `(-> this stack-top)` plus the memory base, and
`thread-suspend`/`thread-resume` copy the live stack out and back to the *same
addresses*. iPadOS objects to executable memory, not to where SP points.

This superseded the hand-written ARM64 emitter (`goalc/emitter/IGenARM64.cpp`
plus per-node lowering in `goalc/compiler/IR.cpp`), which covered roughly 8 of
42 IR node types, each artificially restricted, and had compiled about a dozen
hand-picked functions. That emitter is now dead code pending removal.

## What was implemented

A GOAL function object stays an ordinary basic of type `function` on the GOAL
heap. On ARM64 it holds the **64-bit native entry point** at its address
instead of machine code. `call_goal` / `call_goal_on_stack` load that pointer
through a new `goal_function_entry_point()` rather than jumping into the heap,
which is exactly the load the emitted C already performed via `GOAL_FN`. AOT
functions and the kernel's own C functions therefore become one uniform kind.
`make_function_from_c`, `make_nothing_func`, and `make_zero_func` no longer
emit x86 on ARM64.

Static data and relocations keep using the real linker rules at runtime, as
this document predicted: the loader implements all four V3 kinds with the
semantics from `jak1/klink.cpp`, including `symlink_v3`'s convention that -1
stores the address and anything else stores the s7 offset.
`LINK_DISTANCE_TO_OTHER_SEG_32/64` has no counterpart in this model, because it
is a RIP-relative fixup between code segments and there is no emitted code
segment.

## Evidence

`goal_src/jak1/kernel/gcommon.gc` and `kernel/gstring.gc` load into the real
global heap, their `top-level` functions run through `call_goal`, and functions
are then reached by looking their symbol up in the real symbol table. Observed
identically on host and simulator, both reporting `EE main memory executable:
NO`:

- `top-level` defined 66 symbols and called the kernel's own `(method new type)`
  to create `vec4s` (parent `uint128`, size 16, 9 methods), plus `method-set!`
  for every method.
- Arithmetic and logic including PS2 32-bit sign-extension:
  `(* 100000 100000)` = 1410065408, `(/ -7 2)` = -3, `(mod -7 3)` = -1,
  `(ash -16 -2)` = -4, `(lognot 0)` = `#xffffffffffffffff`.
- `(fact 5)` = 120 and `(fact 10)` = 3628800 — GOAL recursing into itself
  through the `fact` symbol.
- Real heap pairs via the kernel's `new_pair`, with `(method length pair)`
  dispatched through `jak1::call_method_of_type`.
- Cross-file calls into the second object file: `string=`, `string->int`,
  `(method length string)`, and `string-upcase` mutating a real heap string.
- `printl` / `print` reaching the real GOAL print buffer through the string
  type's print method and `format_impl_jak1`.

The linked binary has only ordinary Mach-O segments, and the GOAL functions are
`T` symbols in `__TEXT,__text` — normal signed code.

## Limits

- **No physical-device run.** The device build is link and code-sign evidence
  only.
- **Process allocation from GOAL is shimmed** to `UNKNOWN_PP`, so the `pp` path
  is unusable rather than merely untested.
- Only `LINK_TYPE_PTR` was exercised by real goalc-emitted data; the other three
  relocation kinds were exercised by a synthetic descriptor.
- **The thread and stack routines are implemented.** Seven native ARM64
  routines (`game/kernel/core/goal_native_kernel.cpp` + `goal_thread_arm64.s`)
  cover `return-from-thread`, `reset-and-call`, `thread-suspend`,
  `thread-resume`, `(method new catch-frame)`, `throw-dispatch`, and
  `enter-state-run-code`, built on three assembly primitives (context
  save-and-call, context restore, call-on-stack). The other four of the
  original 11 were rewritten as plain GOAL with identical effect. Zero
  functions remain untranslated: 10,596 lowered to C plus 7 native.
- **511 of 518 object files load in real `game.gp` build order and all 511
  top-levels execute**, reaching 7877 symbols. `time-of-day.gc` spawns a real
  process and `go`es to a state, so catch-frame, throw-dispatch, and
  enter-state run for real. Verified on host and the M5 simulator; the iOS
  build ad-hoc signs with no writable-executable segment.
- A dedicated thread-switch test proves callee-saved register preservation
  across context round-trips, real stack switching, catch/throw with live
  locals, and a suspend/resume round trip in which the C side overwrites all
  368 live stack bytes between resumes and the values still restore.
- **The isolated library proof historically stopped at game data**: file 512,
  `pc/hud-classes-pc.gc`, dereferenced the `*fuelcell-naked-sg*` art group before
  that harness had file I/O or level art. The integrated app now supplies the
  separate data and renderer seams; this older harness limit is not the current
  Jak 1 application boot boundary.
- Machine-layer functions (`cpad-open`, `rpc-call`, `scf-get-*`, …) still
  return 0 through loud stubs; files are proven to LOAD, not proven to work.
- Known tuning debt: `PROCESS_STACK_SAVE_SIZE` (256 bytes) and per-process
  stack sizes were chosen for the PS2; an ARM64 context is 176 bytes and a
  trivial suspending state measured 368 live. `thread-suspend` fails loudly
  with both numbers rather than overrunning; values need retuning as processes
  begin suspending for real.
- **Jak II has separate bounded ARM64 evidence.** Its complete 840-source AOT
  corpus has 18,479 emitted functions plus 7 shared native routines with zero
  coverage failures. The explicit user-data headless probe registers all 840
  units, loads KERNEL 8/8 and GAME 465/465, and runs 100 dispatcher frames. A
  separate thin iPhoneOS ARM64 product final-links all 840 translations plus
  the manifest with `jak2-kernel-core`. Jak II is not wired into Eco Pro and has
  no app signing, Apple simulator/device launch, renderer/audio, title-screen,
  or gameplay validation. Jak 3 and Jak X remain outside this validated model.
