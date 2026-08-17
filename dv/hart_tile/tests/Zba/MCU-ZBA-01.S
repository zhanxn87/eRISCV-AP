/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# RV32Zba directed test: all shifted-add instructions, overflow, aliases, x0,
# and back-to-back forwarding. The register oracle checks exact XLEN wraparound.
  lui    x1, 0x40000
  addi   x1, x1, 1
  lui    x2, 0x40000
  addi   x2, x2, 3
  sh1add x3, x1, x2
  sh2add x4, x1, x2
  sh3add x5, x1, x2
  sh1add x6, x3, x4
  sh2add x0, x1, x2
  addi   x7, x0, 0
  sh3add x2, x2, x1
  sh1add x8, x2, x2
  addi   x9, x0, -1
  sh1add x10, x9, x9
  sh2add x11, x9, x9
  sh3add x12, x9, x9
  nop
  nop
  nop
  nop
