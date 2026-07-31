.text
.p2align 2

; Static C++-to-GOAL boundary for the ARM64 special-register contract:
; x20 = process, x21 = symbol table, x22 = GOAL memory offset base.
.globl _goalpad_call_aot_with_state
_goalpad_call_aot_with_state:
  stp x29, x30, [sp, #-16]!
  mov x29, sp
  stp x19, x20, [sp, #-16]!
  stp x21, x22, [sp, #-16]!
  str x23, [sp, #-16]!

  mov x20, x0
  mov x21, x1
  mov x22, x2
  mov x19, x3
  mov x23, x4

  stp x20, x21, [x23, #0]
  str x22, [x23, #16]
  blr x19
  str x0, [x23, #24]
  stp x20, x21, [x23, #32]
  str x22, [x23, #48]

  ldr x23, [sp], #16
  ldp x21, x22, [sp], #16
  ldp x19, x20, [sp], #16
  ldp x29, x30, [sp], #16
  ret

; Set distinct caller values before invoking the boundary so the C++ probe can
; verify that the boundary restores all three callee-saved special registers.
.globl _goalpad_probe_call_aot_with_state
_goalpad_probe_call_aot_with_state:
  stp x29, x30, [sp, #-16]!
  mov x29, sp
  stp x19, x20, [sp, #-16]!
  stp x21, x22, [sp, #-16]!
  str x23, [sp, #-16]!

  mov x23, x4
  mov x20, #0x14
  mov x21, #0x15
  mov x22, #0x16
  bl _goalpad_call_aot_with_state
  mov x19, x0

  stp x20, x21, [x23, #56]
  str x22, [x23, #72]
  mov x0, x19

  ldr x23, [sp], #16
  ldp x21, x22, [sp], #16
  ldp x19, x20, [sp], #16
  ldp x29, x30, [sp], #16
  ret

; One-argument variant. The ordinary Apple ABI carries arg0 in x0 only after
; X20/X21/X22 have been established for the generated GOAL entry.
.globl _goalpad_call_aot1_with_state
_goalpad_call_aot1_with_state:
  stp x29, x30, [sp, #-16]!
  mov x29, sp
  stp x19, x20, [sp, #-16]!
  stp x21, x22, [sp, #-16]!
  str x23, [sp, #-16]!

  mov x20, x0
  mov x21, x1
  mov x22, x2
  mov x19, x3
  mov x23, x5
  mov x0, x4

  stp x20, x21, [x23, #0]
  str x22, [x23, #16]
  str x0, [x23, #24]
  blr x19
  str x0, [x23, #32]
  stp x20, x21, [x23, #40]
  str x22, [x23, #56]

  ldr x23, [sp], #16
  ldp x21, x22, [sp], #16
  ldp x19, x20, [sp], #16
  ldp x29, x30, [sp], #16
  ret

; Set distinct caller values before the one-argument boundary and record their
; restoration after it returns.
.globl _goalpad_probe_call_aot1_with_state
_goalpad_probe_call_aot1_with_state:
  stp x29, x30, [sp, #-16]!
  mov x29, sp
  stp x19, x20, [sp, #-16]!
  stp x21, x22, [sp, #-16]!
  str x23, [sp, #-16]!

  mov x23, x5
  mov x20, #0x14
  mov x21, #0x15
  mov x22, #0x16
  bl _goalpad_call_aot1_with_state
  mov x19, x0

  stp x20, x21, [x23, #64]
  str x22, [x23, #80]
  mov x0, x19

  ldr x23, [sp], #16
  ldp x21, x22, [sp], #16
  ldp x19, x20, [sp], #16
  ldp x29, x30, [sp], #16
  ret

.subsections_via_symbols
