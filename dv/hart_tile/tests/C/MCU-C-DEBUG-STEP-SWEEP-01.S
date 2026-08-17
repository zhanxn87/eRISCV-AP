/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# eRISCV MCU RV32C debug single-step sweep.
# Steps over several compressed instructions and checks DPC advances by PC+2.

  .section .text
  .globl _start
  .option rvc
_start:
  li x20, 0
  li x21, 0
  li x22, 0
  li x24, 0
  li x25, 0
  li x26, 0
  li x27, 0
  li x28, 0
  li x31, 0
  csrw dscratch1, x0

  lui x5, 0x8            # dcsr.ebreakm=1
  csrw dcsr, x5
  c.ebreak
step0:
  c.addi x20, 1
step1:
  c.li x21, 5
step2:
  c.mv x22, x21
step3:
  c.add x20, x21
after_steps:
  li x5, 6
  sub x24, x20, x5
  li x5, 5
  sub x25, x21, x5
  sub x26, x22, x5
  csrr x6, dscratch1
  li x7, 5
  sub x27, x6, x7
  add x31, x31, x24
  add x31, x31, x25
  add x31, x31, x26
  add x31, x31, x27
pass:
  j pass

  .org 0x100
debug_handler:
  csrr x9, dscratch1
  addi x9, x9, 1
  csrw dscratch1, x9
  csrr x7, dpc

  li x8, 1
  beq x9, x8, dbg_entry_1
  li x8, 2
  beq x9, x8, dbg_entry_2
  li x8, 3
  beq x9, x8, dbg_entry_3
  li x8, 4
  beq x9, x8, dbg_entry_4
  li x8, 5
  beq x9, x8, dbg_entry_5
  li x31, -1
  dret

dbg_entry_1:
  la x8, step0
  sub x10, x7, x8
  or x31, x31, x10
  li x5, 4               # dcsr.step=1
  csrrs x0, dcsr, x5
  dret

dbg_entry_2:
  la x8, step1
  sub x10, x7, x8
  or x31, x31, x10
  dret

dbg_entry_3:
  la x8, step2
  sub x10, x7, x8
  or x31, x31, x10
  dret

dbg_entry_4:
  la x8, step3
  sub x10, x7, x8
  or x31, x31, x10
  dret

dbg_entry_5:
  la x8, after_steps
  sub x10, x7, x8
  or x31, x31, x10
  li x5, 4               # clear dcsr.step
  csrrc x0, dcsr, x5
  dret
