/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# RV32M divider short-path coverage.  The compact nonzero operands exercise
# leading-zero alignment; |a| < |b|, equality, and zero exercise S_SPECIAL.
  addi x1,  x0, 13
  addi x2,  x0, 3
  div  x3,  x1, x2
  rem  x4,  x1, x2
  divu x5,  x1, x2
  remu x6,  x1, x2

  addi x7,  x0, -13
  div  x8,  x7, x2
  rem  x9,  x7, x2

  # |a| < |b|, including a negative dividend and zero.
  addi x10, x0, 5
  addi x11, x0, 7
  div  x12, x10, x11
  rem  x13, x10, x11
  addi x14, x0, -5
  div  x15, x14, x11
  rem  x16, x14, x11
  addi x17, x0, 0
  div  x18, x17, x2
  rem  x19, x17, x2

  # Equal magnitudes must bypass the iterative divider as well.
  divu x20, x11, x11
  remu x21, x11, x11
  nop
  nop
  nop
  nop
  nop
