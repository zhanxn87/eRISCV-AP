/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# RV32Zbb directed test: logical, count, min/max, extension, rotate and byte
# operations. Chained uses exercise EX forwarding for each result class.
  lui    x1, 0x80000
  addi   x1, x1, 1
  addi   x2, x0, 15
  andn   x3, x1, x2
  orn    x4, x1, x2
  xnor   x5, x1, x2
  clz    x6, x1
  ctz    x7, x1
  cpop   x8, x1
  max    x9, x1, x2
  min    x10, x1, x2
  maxu   x11, x1, x2
  minu   x12, x1, x2
  sext.b x13, x1
  sext.h x14, x1
  zext.h x15, x1
  rol    x16, x1, x2
  ror    x17, x1, x2
  rori   x18, x1, 1
  orc.b  x19, x1
  rev8   x20, x1
  clz    x21, x0
  ctz    x22, x0
  cpop   x23, x0
  csrr   x24, misa
  lui    x25, 0x80000
  addi   x26, x0, -1
  max    x27, x25, x26
  minu   x28, x25, x26
  nop
  nop
  nop
  nop
