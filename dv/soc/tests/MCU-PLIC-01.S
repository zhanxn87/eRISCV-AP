/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# eRISCV MCU PLIC v1.0.0 directed test — register access tests.
# PLIC base = 0x0C00_0000.  Large offsets need two-step address calc.

  .section .text
  .globl _start
  .option rvc
_start:
  li x5, 0x0C000000

  # T1: priority[1] at offset 0x4; offset 0 is reserved for source 0.
  li x6, 5
  addi x10, x5, 4
  sw x6, 0(x10)
  lw x7, 0(x10)
  sub x24, x7, x6

  # T2: enable[1] at offset 0x2000
  li x6, 2
  addi x10, x5, 0
  lui x11, 2
  add x10, x10, x11
  sw x6, 0(x10)
  lw x7, 0(x10)
  sub x25, x7, x6

  # T3: pending at offset 0x1000
  addi x10, x5, 0
  lui x11, 1
  add x10, x10, x11
  lw x26, 0(x10)

  # T4: threshold at offset 0x200000
  li x6, 3
  lui x11, 0x200
  add x10, x5, x11
  sw x6, 0(x10)
  lw x7, 0(x10)
  sub x27, x7, x6

  # T5: claim/complete at offset 0x200004
  lui x11, 0x200
  addi x11, x11, 4
  add x10, x5, x11
  lw x28, 0(x10)

  # T6: priority[1] at offset 4
  li x6, 7
  sw x6, 4(x5)
  lw x7, 4(x5)
  sub x29, x7, x6

  # T7: priority[3] at offset 8
  li x6, 2
  sw x6, 8(x5)
  lw x7, 8(x5)
  sub x30, x7, x6

  # Accumulate: x24 must be 0
  add x24, x24, x25
  add x24, x24, x27
  add x24, x24, x29
  add x24, x24, x30

pass:
  j .
fail:
  li x24, -1
  j .
