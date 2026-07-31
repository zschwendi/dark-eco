# AOT execution model for iPadOS

Status: **Investigating.** This document records the analysis that must be
settled before any further ARM64 compiler work. It describes findings from the
existing OpenGOAL source, not implemented GOALPad behavior.

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

### B. Function objects carry a native pointer — recommended

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

Separately tracked. The existing hand-written ARM64 emitter
(`goalc/emitter/IGenARM64.cpp` plus per-node lowering in
`goalc/compiler/IR.cpp`) covers roughly 8 of 42 IR node types, each artificially
restricted, with `IR_FunctionCall`, `IR_GetSymbolValue`, `IR_SetSymbolValue`,
`IR_FloatMath`, `IR_StaticVarAddr`, `IR_StaticVarLoad`, and `IR_FunctionAddr`
all `throw "NYI"`. Roughly a dozen hand-picked Jak 1 functions have been
compiled this way. Jak 1 contains tens of thousands.

An alternative under active evaluation is to emit C from the GOAL IR and compile
it with clang for arm64, which supplies a complete optimizing backend, normal
Mach-O objects, and ordinary code signing. That evaluation must produce a
working prototype over real Jak 1 source before it is adopted or rejected.

## What this does not claim

Nothing here is implemented. No approach has been validated on a physical iPad.
The linker analysis is read from source and has not been exercised against real
extracted game data.
