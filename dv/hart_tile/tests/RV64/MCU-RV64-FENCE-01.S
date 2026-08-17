/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

/* RV64 FENCE must write dirty D-Cache lines to the backing memory before it
 * retires. The companion .fence oracle is sampled at cache flush completion. */

  .section .text
  .option norvc
  .globl _start
_start:
  addi  x1, x0, 128
  li    x2, 0x1122334455667788
  sd    x2, 0(x1)
  fence rw, rw
  ld    x3, 0(x1)
  addi  x4, x0, 1

done:
  jal   x0, done
