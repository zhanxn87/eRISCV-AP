/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

/* RV64M: all XLEN operations, *W operations, and required division corners. */

  .section .text
  .option rvc
  .globl _start
_start:
  addi  x1, x0, -7
  addi  x2, x0, 3
  mul   x3, x1, x2
  mulh  x4, x1, x2
  mulhsu x5, x1, x2
  mulhu x6, x1, x2
  div   x7, x1, x2
  divu  x8, x1, x2
  rem   x9, x1, x2
  remu  x10, x1, x2

  addi  x11, x0, 0
  div   x12, x1, x11
  rem   x13, x1, x11
  addi  x14, x0, 1
  slli  x14, x14, 63
  addi  x15, x0, -1
  div   x16, x14, x15
  rem   x17, x14, x15

  mulw  x18, x1, x2
  divw  x19, x1, x2
  divuw x20, x1, x2
  remw  x21, x1, x2
  remuw x22, x1, x2
  addi  x23, x0, 1
  slliw x23, x23, 31
  divw  x24, x23, x15
  remw  x25, x23, x15
  divw  x26, x1, x11
  remw  x27, x1, x11

done:
  j     done
