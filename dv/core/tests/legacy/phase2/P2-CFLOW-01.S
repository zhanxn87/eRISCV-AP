/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# Phase 2 control-flow bring-up test.
# All branch operands are written before the initial NOP separation.

  addi x1, x0, 1
  addi x2, x0, 2
  addi x3, x0, -1
  nop
  nop
  nop
  nop

  beq  x1, x1, 1f
  addi x4, x0, 99
1: addi x4, x0, 4
  bne  x1, x1, 2f
  addi x5, x0, 5
2: blt  x1, x2, 3f
  addi x6, x0, 99
3: addi x6, x0, 6
  bge  x1, x2, 4f
  addi x7, x0, 7
4: bltu x1, x2, 5f
  addi x8, x0, 99
5: addi x8, x0, 8
  bgeu x1, x2, 6f
  addi x9, x0, 9

6: jal  x10, 7f
  addi x11, x0, 99
7: addi x11, x0, 11
  auipc x12, 0
  nop
  nop
  nop
  nop
  jalr x13, x12, 28
  addi x14, x0, 99
  addi x14, x0, 14

  # Deterministic padding for the fixed watchdog window.
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
