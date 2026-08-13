/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# Phase 4 load/store bring-up test.
# Covers load/store byte lanes, sign/zero extension, store forwarding, and load-use stalls.

  lui  x1,  0x40
  addi x1,  x1, 0x200
  lui  x2,  0x11223
  addi x2,  x2, 0x344
  sw   x2,  0(x1)
  lw   x3,  0(x1)
  addi x4,  x3, 1

  lb   x5,  0(x1)
  lbu  x6,  1(x1)
  lh   x7,  0(x1)
  lhu  x8,  2(x1)

  addi x9,  x0, -1
  sb   x9,  1(x1)
  lw   x10, 0(x1)

  addi x11, x0, -128
  sb   x11, 3(x1)
  lb   x12, 3(x1)
  lbu  x13, 3(x1)

  addi x14, x0, -2
  sh   x14, 2(x1)
  lh   x15, 2(x1)
  lhu  x16, 2(x1)

  addi x17, x0, 7
  sw   x17, 8(x1)
  lw   x18, 8(x1)
  addi x19, x18, 5

  addi x20, x1, 12
  sw   x19, 0(x20)
  lw   x21, 0(x20)
