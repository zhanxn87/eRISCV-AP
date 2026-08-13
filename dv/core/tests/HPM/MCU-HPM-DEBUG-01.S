/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# MCU-HPM-DEBUG-01: DEBUG_ENTRY HPM event through EBREAK/DRET.

  .section .text
  .globl _start
  .option norvc
_start:
  csrw  mhpmevent3, x0
  csrw  mhpmcounter3, x0
  li    x1, 18
  csrw  mhpmevent3, x1

  # DCSR.EBREAKM causes the following EBREAK to enter Debug Mode.
  lui   x1, 0x8
  csrw  dcsr, x1
  ebreak
after_debug:
  csrw  mhpmevent3, x0
  csrr  x2, mhpmcounter3
  sltu  x24, x0, x2
  li    x28, 1
done:
  jal   x0, done

  .org 0x100
debug_handler:
  dret
