/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# eRISCV MCU CLINT MTIP interrupt-directed test.

  .section .text
  .globl _start
  .option rvc
_start:
  la x5, mtip_handler
  csrw mtvec, x5

  li x5, 0x02000000      # CLINT_BASE
  li x6, 0x4000
  add x6, x5, x6         # MTIMECMP low
  lui x7, 0xc
  addi x7, x7, -8
  add x7, x5, x7         # MTIME low

  sw x0, 4(x6)           # mtimecmp high = 0
  li x8, 200
  sw x8, 0(x6)           # mtimecmp low = 200
  sw x0, 4(x7)           # mtime high = 0
  sw x0, 0(x7)           # mtime low = 0

  li x8, 0x80            # mie.MTIE
  csrs mie, x8
  li x8, 0x8             # mstatus.MIE
  csrs mstatus, x8

  li x24, -1
wait_mtip:
  bnez x24, wait_mtip
pass:
  j pass

mtip_handler:
  csrr x8, mcause
  li x9, 0x80000007
  bne x8, x9, mtip_bad

  li x5, 0x02000000
  li x6, 0x4000
  add x6, x5, x6
  li x7, -1
  sw x7, 0(x6)           # mtimecmp low = all ones
  sw x7, 4(x6)           # mtimecmp high = all ones; deassert MTIP
  li x24, 0
  mret
mtip_bad:
  li x24, -2
  mret
