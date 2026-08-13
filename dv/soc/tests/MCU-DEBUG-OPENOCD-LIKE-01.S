/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# Debug JTAG/OpenOCD-style test program.
# The SoC TB halts this loop and drives the Debug Module through JTAG DMI.

  .section .text
  .globl _start
  .option rvc
_start:
  lui x5, 0x12345
  addi x5, x5, 0x678
loop:
  j loop
