/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# eRISCV MCU external PLIC source 17-32 sweep.
# TB asserts one source at a time; handler claims/completes each source.

  .section .text
  .globl _start
  .option rvc
_start:
  li sp, 0x11010000
  la x5, plic_handler
  csrw mtvec, x5

  li x5, 0x0C000000

  # priority[1..32] = 1
  addi x6, x5, 4
  li x7, 32
  li x8, 1
priority_loop:
  sw x8, 0(x6)
  addi x6, x6, 4
  addi x7, x7, -1
  bnez x7, priority_loop

  # enable external sources 17..31 in word0, source32 in word1
  lui x6, 2
  add x6, x5, x6
  li x7, 0xfffe0000
  sw x7, 0(x6)
  li x7, 1
  sw x7, 4(x6)

  # threshold = 0
  lui x6, 0x200
  add x6, x5, x6
  sw x0, 0(x6)

  li x20, 0      # count
  li x21, 0      # sum of claimed IDs
  li x22, 0      # error flag
  li x24, -1

  li x6, 0x800
  csrs mie, x6
  li x6, 0x8
  csrs mstatus, x6

wait_done:
  li x6, 16
  bne x20, x6, wait_done
  bnez x22, fail
  li x6, 392     # 17+...+32
  sub x24, x21, x6
pass:
  j pass
fail:
  li x24, -1
  j fail

  .balign 4
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
  add x21, x21, x7
  addi x20, x20, 1
  sw x7, 0(x6)
  mret
plic_bad:
  li x22, 1
  li x20, 16
  mret
