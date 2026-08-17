/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# MCU-M-CTRL-01: Multi-cycle M/D control verification.
#
# Covers a TB-synchronized interrupt during MUL, back-to-back/dependent M/D,
# ECALL trap handling, and divide corner cases.
#
# Self-checking: x28 = 1 at done = PASS.

  .globl _start
_start:
  la    x31, handler
  csrw  mtvec, x31

  li    x2, 0x800
  csrs  mie, x2
  li    x2, 8
  csrs  mstatus, x2
  li    x27, 0

  # =========================================================================
  # P3.3 — Back-to-back MUL → dependent consumer
  # =========================================================================
  li    x10, 100
  li    x11, 200
interrupt_mul:
  mul   x14, x10, x11           # 20000
  addi  x15, x14, 1             # dependent on x14
  li    x1, 20001
  bne   x15, x1, fail
  li    x1, 1
  bne   x27, x1, fail

  # =========================================================================
  # P3.4 — Back-to-back DIV → dependent consumer
  # =========================================================================
  li    x10, 500
  li    x11, 3
  div   x16, x10, x11           # 166
  addi  x17, x16, 5             # dependent on x16
  li    x1, 171
  bne   x17, x1, fail

  # =========================================================================
  # P3.5 — Mixed MUL → DIV → REM back-to-back
  # =========================================================================
  li    x10, 25
  li    x11, 40
  mul   x18, x10, x11           # 1000
  li    x10, 7
  div   x19, x18, x10           # 1000 / 7 = 142
  li    x1, 142
  bne   x19, x1, fail
  rem   x20, x18, x10           # 1000 % 7 = 6
  li    x1, 6
  bne   x20, x1, fail

  # =========================================================================
  # P3.6 — Trap (ecall) during multiply: flush verification
  # =========================================================================
  li    x10, 100
  li    x11, 200
  ecall                         # trap →
  # Handler skips to here (mepc+4)
  mul   x21, x10, x11           # After ecall return, MUL executes
  li    x1, 20000
  bne   x21, x1, fail

  # =========================================================================
  # P3.7 — Divide corner cases
  # =========================================================================
  li    x10, 42
  div   x22, x10, x0            # div by zero → -1
  li    x1, -1
  bne   x22, x1, fail

  lui   x10, 0x80000            # INT32_MIN
  li    x11, -1
  div   x23, x10, x11           # overflow → INT32_MIN
  lui   x1, 0x80000
  bne   x23, x1, fail

  li    x28, 1
  jal   x0, done

fail:
  li    x28, 0

done:
  jal   x0, done

  .balign 256
handler:
  csrr  x29, mepc
  csrr  x30, mcause
  li    x2, 0x8000000b
  beq   x30, x2, interrupt_handler
  li    x2, 11
  bne   x30, x2, fail
  addi  x29, x29, 4
  csrw  mepc, x29
  mret
interrupt_handler:
  li    x26, 1
  # The TB intentionally holds this level-triggered IRQ across the M/D
  # completion boundary. Mask MEIE before MRET so there is exactly one
  # architecturally handled interrupt.
  li    x2, 0x800
  csrc  mie, x2
  la    x2, interrupt_mul
  bne   x29, x2, fail
  li    x26, 3
  li    x27, 1
  mret
