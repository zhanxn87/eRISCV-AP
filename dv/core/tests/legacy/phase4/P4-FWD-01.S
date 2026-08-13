/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# Phase 4 forwarding bring-up test.
# This testcase intentionally removes NOP dependency spacing.

  addi x1,  x0, 1
  addi x2,  x1, 2
  add  x3,  x2, x1
  add  x4,  x3, x2
  add  x5,  x0, x4
  addi x0,  x0, 99
  add  x6,  x0, x0

  addi x7,  x0, 10
  addi x8,  x7, 0
  beq  x8,  x7, 1f
  addi x9,  x0, 99
1: addi x9,  x0, 9

  addi x12, x0, 0x40
  jalr x13, x12, 0
  addi x14, x0, 99
  addi x15, x0, 77
2: addi x14, x0, 14

  addi x15, x0, 20
  addi x16, x0, 3
  add  x17, x15, x16
  addi x18, x17, 1
