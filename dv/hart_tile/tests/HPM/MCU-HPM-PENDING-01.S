/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# MCU-HPM-PENDING-01: IRQ_PENDING_CYCLES from the raw external IRQ input.
#
# MIE stays clear.  WFI therefore wakes on the testbench-driven input without
# taking a trap, isolating the pending-line qualifier from INTERRUPT_TAKEN.

  .section .text
  .globl _start
  .option norvc
_start:
  csrw  mhpmevent4, x0
  csrw  mhpmcounter4, x0
  li    x1, 19
  csrw  mhpmevent4, x1
  wfi
  csrw  mhpmevent4, x0
  csrr  x2, mhpmcounter4
  sltu  x24, x0, x2
  li    x28, 1
done:
  jal   x0, done
