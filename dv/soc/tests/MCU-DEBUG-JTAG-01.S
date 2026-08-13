/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

  .section .text
  .globl _start
_start:
  lui x5, 0x12345
  addi x5, x5, 0x678
loop:
  jal x0, loop
