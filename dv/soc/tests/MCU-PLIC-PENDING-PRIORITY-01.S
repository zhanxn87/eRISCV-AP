/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# eRISCV MCU PLIC concurrent pending, priority, and tie-order test.
# TB first asserts sources 17+21, then sources 18+19. Expected claim order: 21,17,18,19.

  .section .text
  .globl _start
  .option rvc
_start:
  li sp, 0x11010000
  la x5, plic_handler
  csrw mtvec, x5

  li x5, 0x0C000000
  li x6, 3
  sw x6, 68(x5)   # source 17 priority 3
  li x6, 4
  sw x6, 72(x5)   # source 18 priority 4
  sw x6, 76(x5)   # source 19 priority 4; lower ID should win tie
  li x6, 6
  sw x6, 84(x5)   # source 21 priority 6

  lui x6, 2
  add x6, x5, x6
  li x7, 0x2e0000  # enable sources 17,18,19,21
  sw x7, 0(x6)

  lui x6, 0x200
  add x6, x5, x6
  sw x0, 0(x6)     # threshold = 0

  li x20, 0
  li x21, 0
  li x22, 0
  li x23, 0
  li x24, 0
  li x25, -1
  li x26, 0        # error flag

  li x6, 0x800
  csrs mie, x6
  li x6, 0x8
  csrs mstatus, x6

wait_done:
  li x6, 4
  bne x20, x6, wait_done
  bnez x26, fail
  li x6, 21
  sub x25, x21, x6
  li x6, 17
  sub x6, x22, x6
  add x25, x25, x6
  li x6, 18
  sub x6, x23, x6
  add x25, x25, x6
  li x6, 19
  sub x6, x24, x6
  add x25, x25, x6
pass:
  j pass
fail:
  li x25, -1
  j fail

plic_handler:
  csrr x5, mcause
  li x6, 0x8000000b
  bne x5, x6, plic_bad
  li x5, 0x0C000000
  lui x6, 0x200
  addi x6, x6, 4
  add x6, x5, x6
  lw x7, 0(x6)
  beqz x7, plic_bad
  beqz x20, record_first
  li x5, 1
  beq x20, x5, record_second
  li x5, 2
  beq x20, x5, record_third
  add x24, x7, x0
  j record_done
record_first:
  add x21, x7, x0
  j record_done
record_second:
  add x22, x7, x0
  j record_done
record_third:
  add x23, x7, x0
record_done:
  addi x20, x20, 1
  sw x7, 0(x6)
  mret
plic_bad:
  li x26, 1
  li x20, 4
  mret
