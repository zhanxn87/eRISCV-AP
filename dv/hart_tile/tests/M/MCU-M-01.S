/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# RV32M directed coverage: all eight operations plus mandated corner cases.
# x1 = -7, x2 = 3, x11 = 0, x14 = INT32_MIN, x15 = -1
  addi x1,  x0, -7
  addi x2,  x0, 3
  mul    x3,  x1, x2
  mul    x19, x3, x2
  mulh   x4,  x1, x2
  mulhsu x5,  x1, x2
  mulhu  x6,  x1, x2
  div    x7,  x1, x2
  divu   x8,  x1, x2
  rem    x9,  x1, x2
  remu   x10, x1, x2
  addi   x11, x0, 0
  div    x12, x1, x11
  rem    x13, x1, x11
  lui    x14, 0x80000
  addi   x15, x0, -1
  div    x16, x14, x15
  rem    x17, x14, x15
  csrr   x18, misa
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
