/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# eRISCV MCU RV32C stack-pointer immediate directed test.
# Covers c.addi4spn and c.addi16sp normal and boundary immediates.

  .section .text
  .globl _start
  .option rvc
_start:
  li sp, 0x11010000
  li x24, 0
  li x25, 0
  li x26, 0
  li x27, 0
  li x28, 0
  li x29, 0
  li x30, 0
  li x31, 0

  c.addi4spn x8, sp, 4
  mv x9, sp
  addi x9, x9, 4
  sub x24, x8, x9

  c.addi4spn x15, sp, 1020
  mv x9, sp
  li x10, 1020
  add x9, x9, x10
  sub x25, x15, x9

  mv x9, sp
  c.addi16sp sp, 16
  addi x9, x9, 16
  sub x26, sp, x9

  mv x9, sp
  c.addi16sp sp, -16
  addi x9, x9, -16
  sub x27, sp, x9

  mv x9, sp
  c.addi16sp sp, 496
  li x10, 496
  add x9, x9, x10
  sub x28, sp, x9

  mv x9, sp
  c.addi16sp sp, -512
  li x10, -512
  add x9, x9, x10
  sub x29, sp, x9

  add x31, x24, x25
  add x31, x31, x26
  add x31, x31, x27
  add x31, x31, x28
  add x31, x31, x29
pass:
  j pass
