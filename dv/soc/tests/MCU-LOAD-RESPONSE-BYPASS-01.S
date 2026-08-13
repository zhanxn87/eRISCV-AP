/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# MCU-LOAD-RESPONSE-BYPASS-01: a multi-cycle IMEM-window D-bus load supplies
# an immediately following branch or store-data consumer. The consumer may
# enter EX early, but mem_wait must hold it until the exact load response is
# available. Neither dependency should increment the load-use stall counter.

  .section .text
  .globl _start
  .option norvc

_start:
  lui   x1, 0x11000             # DTCM base
  la    x2, test_word           # IMEM address, read through the D-bus
  li    x4, 0x13579bdf

  csrw  mhpmevent6, x0
  csrw  mhpmcounter6, x0
  li    x10, 11                 # HPM_EVENT_LOAD_USE_STALL_CYCLES
  csrw  mhpmevent6, x10

  lw    x3, 0(x2)
  beq   x3, x4, branch_data_ok
  jal   x0, fail

branch_data_ok:
  lw    x5, 0(x2)
  sw    x5, 0(x1)               # load -> store data; address is independent

  csrw  mhpmevent6, x0
  csrr  x25, mhpmcounter6
  bnez  x25, fail

  lw    x6, 0(x1)
  bne   x6, x4, fail
  li    x24, 1
  jal   x0, done

fail:
  li    x24, 0

done:
  jal   x0, done

  .balign 4
test_word:
  .word 0x13579bdf
