/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# MCU-LMEM-LOAD-BRANCH-01: an accepted DTCM load supplies an immediately
# following conditional branch from the same-cycle MEM response. HPM6 must
# remain zero: the branch must not take the conservative ID/EX load-use stall.

  .section .text
  .globl _start
  .option norvc

_start:
  lui   x1, 0x11000             # DTCM base
  li    x3, 0                   # stale value must fail the branch
  li    x4, 42
  sw    x4, 0(x1)
  nop                           # let the preceding store vacate the SRAM port
  nop

  csrw  mhpmevent6, x0
  csrw  mhpmcounter6, x0
  li    x5, 11                  # HPM_EVENT_LOAD_USE_STALL_CYCLES
  csrw  mhpmevent6, x5

  lw    x3, 0(x1)
  beq   x3, x4, branch_data_ok  # immediate load-to-branch dependency

fail:
  li    x24, 0
  jal   x0, done

branch_data_ok:
  csrw  mhpmevent6, x0
  csrr  x25, mhpmcounter6
  bnez  x25, fail
  li    x24, 1

done:
  jal   x0, done
