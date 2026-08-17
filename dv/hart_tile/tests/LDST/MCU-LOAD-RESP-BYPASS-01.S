/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# M2 load-response forwarding guard.
#
# A dependent ADD follows LW immediately. HPM6 counts LOAD_USE_STALL_CYCLES:
# ID/EX hazard detection and the fixed one-cycle DTCM response require two
# cycles. A third EX/MEM bubble is not allowed after the response is accepted
# into MEM/WB. x30 must therefore be two, while x4 proves forwarding.

  .section .text
  .globl _start
  .option norvc

_start:
  lui   x1, 0x11000             # DTCM base; do not exercise DBus-to-IMEM arbitration
  li    x2, 0x2a
  sw    x2, 0(x1)

  csrw  mhpmevent6, x0
  csrw  mhpmcounter6, x0
  li    x5, 11                  # HPM_EVENT_LOAD_USE_STALL_CYCLES
  csrw  mhpmevent6, x5

  lw    x3, 0(x1)
  add   x4, x3, x2              # immediate dependent consumer

  csrw  mhpmevent6, x0
  csrr  x30, mhpmcounter6
  li    x5, 2
  sub   x29, x30, x5
  li    x5, 84
  sub   x28, x4, x5

done:
  jal   x0, done
