/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# eRISCV MCU Debug 1.0 abstract GPR sweep test program.
# The SoC TB halts this loop, writes/reads x0-x31 through abstract access, then resumes.

  .section .text
  .globl _start
  .option rvc
_start:
  lui x5, 0x12345
  addi x5, x5, 0x678
loop:
  j loop
