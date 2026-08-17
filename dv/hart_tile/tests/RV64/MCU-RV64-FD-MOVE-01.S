/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

/* RV64D FPR bit-pattern transfer through the core pipeline. */

  .section .text
  .option norvc
  .globl _start
_start:
  li      x31, 0x0000000000006000
  csrrs   x0, mstatus, x31
  li      x1, 0x3ff0000000000000
  li      x2, 0x4000000000000000
  fmv.d.x f1, x1
  fmv.d.x f2, x2
  fmv.x.d x3, f1
  fmv.x.d x4, f2

done:
  j done
