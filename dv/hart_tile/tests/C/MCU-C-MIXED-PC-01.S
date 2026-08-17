/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# eRISCV MCU RV32C mixed 16-bit/32-bit PC sequencing directed test.
# Verifies PC+2/PC+4 label spacing, mixed execution, branch target, and c.jal link.

  .section .text
  .globl _start
  .option rvc
_start:
  li x24, 0
  li x25, 0
  li x26, 0
  li x27, 0
  li x28, 0
  li x29, 0
  li x30, 0
  li x31, 0

  la x5, c_after
  la x6, c_before
  sub x24, x5, x6
  addi x24, x24, -2
c_before:
  c.nop
c_after:

  la x5, wide_after
  la x6, wide_before
  sub x25, x5, x6
  addi x25, x25, -4
  .option push
  .option norvc
wide_before:
  addi x10, x10, 1
wide_after:
  .option pop

  li x10, 0
  c.addi x10, 1
  .option push
  .option norvc
  addi x10, x10, 2
  .option pop
  c.addi x10, 3
  li x11, 6
  sub x26, x10, x11

  c.li x8, 0
  c.beqz x8, branch_taken
  li x27, 99
branch_taken:
  li x12, 0
  c.addi x12, 1
  li x13, 1
  sub x27, x12, x13

  la x5, jal_link
  c.jal jal_target
jal_link:
  li x28, 99
jal_target:
  sub x28, x1, x5

  add x31, x24, x25
  add x31, x31, x26
  add x31, x31, x27
  add x31, x31, x28
pass:
  j pass
