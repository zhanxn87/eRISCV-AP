/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

.section .text.eriscv_mcu_trap_entry, "ax"
.balign 4
.globl eriscv_mcu_trap_entry
.type eriscv_mcu_trap_entry, @function
eriscv_mcu_trap_entry:
  addi sp, sp, -64
  sw ra,  0(sp)
  sw t0,  4(sp)
  sw t1,  8(sp)
  sw t2, 12(sp)
  sw t3, 16(sp)
  sw t4, 20(sp)
  sw t5, 24(sp)
  sw t6, 28(sp)
  sw a0, 32(sp)
  sw a1, 36(sp)
  sw a2, 40(sp)
  sw a3, 44(sp)
  sw a4, 48(sp)
  sw a5, 52(sp)
  sw a6, 56(sp)
  sw a7, 60(sp)

  csrr a0, mcause
  csrr a1, mepc
  csrr a2, mtval
  call eriscv_mcu_trap_handler
  csrw mepc, a0

  lw ra,  0(sp)
  lw t0,  4(sp)
  lw t1,  8(sp)
  lw t2, 12(sp)
  lw t3, 16(sp)
  lw t4, 20(sp)
  lw t5, 24(sp)
  lw t6, 28(sp)
  lw a0, 32(sp)
  lw a1, 36(sp)
  lw a2, 40(sp)
  lw a3, 44(sp)
  lw a4, 48(sp)
  lw a5, 52(sp)
  lw a6, 56(sp)
  lw a7, 60(sp)
  addi sp, sp, 64
  mret
