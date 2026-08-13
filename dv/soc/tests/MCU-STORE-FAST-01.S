/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# MCU-STORE-FAST-01: accepted DTCM, CLINT, and PLIC writes retire without a
# delayed D-bus response. HPM5 counts DATA_WAIT_CYCLES, so x30 must remain
# zero across the three stores. The subsequent reads prove the writes reached
# their targets; they occur after the counter is disabled.

  .section .text
  .globl _start
  .option norvc

_start:
  csrw  mhpmevent5, x0
  csrw  mhpmcounter5, x0
  li    x7, 9                   # HPM_EVENT_DATA_WAIT_CYCLES
  csrw  mhpmevent5, x7

  lui   x1, 0x11000             # DTCM base
  li    x7, 0x2a
  sw    x7, 0(x1)

  lui   x2, 0x02000             # CLINT MSIP
  sw    x0, 0(x2)

  lui   x3, 0x0c000             # PLIC priority register 0
  sw    x0, 0(x3)

  csrw  mhpmevent5, x0
  csrr  x30, mhpmcounter5

  lw    x4, 0(x1)
  lw    x5, 0(x2)
  lw    x6, 0(x3)
  add   x24, x4, x5
  add   x24, x24, x6

done:
  jal   x0, done
