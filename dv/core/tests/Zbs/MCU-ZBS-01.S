/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# RV32Zbs directed test: register and immediate forms, including bit 31 and
# chained bit-index forwarding.
  lui    x1, 0x80000
  addi   x1, x1, 1
  addi   x2, x0, 31
  bset   x3, x1, x2
  bclr   x4, x1, x2
  binv   x5, x1, x2
  bext   x6, x1, x2
  bseti  x7, x0, 5
  bclri  x8, x1, 31
  binvi  x9, x1, 0
  bexti  x10, x1, 31
  bset   x11, x0, x0
  bclr   x12, x11, x0
  binv   x13, x0, x0
  bext   x14, x13, x0
  bseti  x15, x0, 31
  nop
  nop
  nop
  nop
