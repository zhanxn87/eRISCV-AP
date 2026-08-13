/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# Four-entry return-address-stack integration guard shared with M0.

  .option norvc
  .globl _start
_start:
  li    x2, 0
  li    x9, 0
  li    x10, 0

  jal   x1, x1_outer
  li    x9, 0x11
after_x1_outer:
  jal   x5, x5_leaf
  li    x12, 0x33
after_x5_leaf:
  li    x11, 7
  bne   x2, x11, fail
  li    x11, 0x11
  bne   x9, x11, fail
  li    x11, 0x22
  bne   x10, x11, fail
  li    x11, 0x33
  bne   x12, x11, fail
  li    x28, 1
  jal   x0, done

x1_outer:
  addi  x8, x1, 0
  jal   x1, x1_inner
  li    x10, 0x22
after_x1_inner:
  addi  x2, x2, 2
  addi  x1, x8, 0
  jalr  x0, 0(x1)

x1_inner:
  addi  x2, x2, 1
  jalr  x0, 0(x1)

x5_leaf:
  addi  x2, x2, 4
  jalr  x0, 0(x5)

fail:
  li    x28, 0
done:
  jal   x0, done
