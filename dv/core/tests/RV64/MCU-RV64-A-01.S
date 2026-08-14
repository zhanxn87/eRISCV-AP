/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

/* RV64A LR/SC reservation semantics and every AMO.D operation, plus
 * sign-extended AMO.W results.  The ordinary SD between LR/SC must clear the
 * reservation and force SC.D to return one. */

  .section .text
  .option norvc
  .globl _start
_start:
  addi x1, x0, 0
  addi x2, x0, 5
  sd   x2, 0(x1)
  lr.d.aq x3, (x1)
  addi x4, x0, 7
  sc.d.rl x5, x4, (x1)
  ld   x6, 0(x1)

  lr.d x7, (x1)
  sd   x2, 0(x1)
  sc.d x8, x4, (x1)
  ld   x9, 0(x1)

  addi x10, x0, 8
  addi x11, x0, 10
  sd   x11, 0(x10)
  addi x12, x0, 3
  amoswap.d x13, x12, (x10)
  amoadd.d  x14, x12, (x10)
  amoxor.d  x15, x12, (x10)
  amoand.d  x16, x12, (x10)
  amoor.d   x17, x12, (x10)

  addi x18, x0, 16
  addi x19, x0, -4
  sd   x19, 0(x18)
  addi x20, x0, 2
  amomin.d x21, x20, (x18)
  amomax.d x22, x20, (x18)

  addi x23, x0, 24
  addi x24, x0, -1
  sd   x24, 0(x23)
  addi x25, x0, 1
  amominu.d x26, x25, (x23)
  addi x27, x0, -1
  amomaxu.d x28, x27, (x23)

  addi x29, x0, 32
  addi x30, x0, -2
  sw   x30, 0(x29)
  lr.w x30, (x29)
  addi x31, x0, 4
  sc.w x30, x31, (x29)
  lw   x31, 0(x29)

  addi x29, x0, 36
  lui  x30, 0x80000
  sw   x30, 0(x29)
  addi x31, x0, 1
  amomin.w  x27, x31, (x29)
  sw        x31, 0(x29)
  lui       x30, 0x80000
  amomaxu.w x28, x30, (x29)
  addi      x30, x0, 2
  amomax.w  x26, x30, (x29)
  lw        x25, 0(x29)

done:
  jal x0, done
