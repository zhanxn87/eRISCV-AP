/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# eRISCV MCU RV32C debug DPC directed test.
# Verifies compressed ebreak and compressed single-step use PC+2 DPC.

  .section .text
  .globl _start
  .option rvc
_start:
  li x24, 0
  li x25, 0
  li x26, 0

  la x10, step_instr
  la x11, after_step

  # Enable ebreak-to-debug. The debug handler sets dcsr.step before DRET.
  lui x5, 0x8
  csrw dcsr, x5
  c.ebreak
step_instr:
  c.nop
after_step:
  sub x24, x13, x10
  sub x25, x14, x11
  csrr x8, dscratch1
  li x9, 2
  sub x26, x8, x9
pass:
  j pass

  .org 0x100
debug_handler:
  csrr x9, dscratch1
  addi x9, x9, 1
  csrw dscratch1, x9
  csrr x7, dpc
  li x8, 1
  bne x9, x8, second_entry
  addi x13, x7, 0
  li x5, 4
  csrrs x0, dcsr, x5
  dret
second_entry:
  addi x14, x7, 0
  li x5, 4
  csrrc x0, dcsr, x5
  dret
