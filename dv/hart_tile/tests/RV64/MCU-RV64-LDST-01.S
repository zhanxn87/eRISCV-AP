/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

/* RV64 load/store widths, sign extension, zero extension, and byte lanes. */

  .section .text
  .option rvc
  .globl _start
_start:
  addi  x1, x0, -1
  sb    x1, 0(x0)
  sh    x1, 2(x0)
  sw    x1, 4(x0)
  sd    x1, 8(x0)
  lb    x2, 0(x0)
  lbu   x3, 0(x0)
  lh    x4, 2(x0)
  lhu   x5, 2(x0)
  lw    x6, 4(x0)
  lwu   x7, 4(x0)
  ld    x8, 8(x0)

  li    x10, 0x0123456789abcdef
  sd    x10, 16(x0)
  addi  x11, x0, 0x80
  sb    x11, 17(x0)
  lh    x12, 16(x0)
  lhu   x13, 16(x0)
  lb    x14, 17(x0)
  lbu   x15, 17(x0)
  ld    x16, 16(x0)
  li    x17, 0x8001
  sh    x17, 20(x0)
  lh    x18, 20(x0)
  lhu   x19, 20(x0)
  ld    x20, 16(x0)

done:
  j     done
