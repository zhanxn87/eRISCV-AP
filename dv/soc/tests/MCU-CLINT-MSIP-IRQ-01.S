/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# eRISCV MCU CLINT MSIP interrupt-directed test.

  .section .text
  .globl _start
  .option rvc
_start:
  la x5, msip_handler
  csrw mtvec, x5

  li x5, 0x02000000      # CLINT_BASE
  sw x0, 0(x5)           # clear MSIP

  li x6, 0x8             # mie.MSIE and mstatus.MIE bit value
  csrs mie, x6
  csrs mstatus, x6

  li x24, -1
  li x6, 1
  sw x6, 0(x5)           # set MSIP

wait_msip:
  bnez x24, wait_msip
pass:
  j pass

msip_handler:
  csrr x6, mcause
  li x7, 0x80000003
  bne x6, x7, msip_bad
  li x5, 0x02000000
  sw x0, 0(x5)           # clear MSIP before mret
  li x24, 0
  mret
msip_bad:
  li x24, -2
  mret
