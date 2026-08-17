/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# Phase 7 load/store stress test.
# Covers load-use stalls, ALU-after-load forwarding, store-data forwarding,
# store-address forwarding, and wrong-path store kill after a taken branch.

  addi x1,  x0, 0
  lui  x2,  0x12345
  addi x2,  x2, 0x678
  sw   x2,  0(x1)
  lw   x3,  0(x1)
  addi x4,  x3, 1
  add  x5,  x4, x3
  sw   x5,  4(x1)
  lw   x6,  4(x1)
  addi x7,  x6, 2

  addi x8,  x0, 1
  beq  x8,  x8, branch_ok
  sw   x0,  4(x1)
branch_ok:
  lw   x9,  4(x1)
  addi x10, x9, 3

  addi x11, x0, 8
  add  x12, x11, x1
  sw   x10, 0(x12)
  lw   x13, 8(x1)
done:
  jal  x0, done
