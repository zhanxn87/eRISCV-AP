/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# eRISCV MCU RV32C interrupt MEPC directed test.
# Sets MSIP immediately before a self-looping compressed instruction at a
# halfword-aligned PC.  The loop removes any dependency on interrupt-observe
# latency while requiring MEPC to preserve that compressed return address.

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

  li x20, 0
  li x8, -1
  li x24, -1
  li x25, -1
  li x26, -1
  li x27, -1

  li x6, 1
  .balign 4
  c.nop                  # place following 32-bit store at PC % 4 == 2
  sw x6, 0(x5)           # set MSIP
irq_return:
  c.bnez x8, irq_return  # hold at the halfword-aligned interrupt boundary
after_irq:
  c.addi x20, 1
  c.addi x20, 1

  li x27, 0              # proves mret returned to the mainline after handler
pass:
  j pass

  .balign 4
msip_handler:
  csrr x6, mcause
  li x7, 0x80000003
  bne x6, x7, irq_bad

  csrr x6, mepc
  la x7, irq_return
  sub x25, x6, x7
  andi x8, x6, 2
  li x9, 2
  sub x26, x8, x9

  li x5, 0x02000000
  sw x0, 0(x5)           # clear MSIP before mret
  li x8, 0               # release irq_return after mret
  li x24, 0
  mret
irq_bad:
  li x24, -2
  mret
