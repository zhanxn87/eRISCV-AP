/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

  .option norvc

  .section .text
  .globl main
  .type main, @function
main:
  la t0, boot_data
  lw t1, 0(t0)
  li t2, 0x13579bdf
  bne t1, t2, fail_data

  la t0, boot_bss
  lw t1, 0(t0)
  bne t1, zero, fail_bss

  la t0, boot_noinit
  lw t1, 0(t0)
  li t2, 0xa5a55a5a
  bne t1, t2, fail_noinit

  li x5, 1
pass:
  j pass

fail_data:
  li x5, 0xd1
  j fail_data

fail_bss:
  li x5, 0xd2
  j fail_bss

fail_noinit:
  li x5, 0xd3
  j fail_noinit

  .section .data
  .balign 4
boot_data:
  .word 0x13579bdf

  .section .bss
  .balign 4
boot_bss:
  .word 0

  .section .noinit
  .balign 4
boot_noinit:
  .word 0

  .section .text.eriscv_mcu_trap_entry, "ax"
  .balign 4
  .globl eriscv_mcu_trap_entry
eriscv_mcu_trap_entry:
  j eriscv_mcu_trap_entry
