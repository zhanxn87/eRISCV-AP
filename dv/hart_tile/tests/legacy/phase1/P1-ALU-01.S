/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# Phase 1 RV32I non-control-flow ALU bring-up test.
# No branch, jump, load, store, CSR, or system instruction is used.

  addi x13, x0, -16
  addi x1,  x0, 5
  addi x2,  x0, 9
  nop
  nop
  nop
  nop

  add  x3,  x1, x2
  sub  x4,  x1, x2
  sll  x5,  x1, x2
  slt  x6,  x1, x2
  sltu x7,  x1, x2
  xor  x8,  x1, x2
  srl  x9,  x1, x2
  sra  x10, x1, x2
  or   x11, x1, x2
  and  x12, x1, x2

  slti  x15, x1, 6
  sltiu x16, x1, 4
  xori  x17, x1, 3
  ori   x18, x1, 0x20
  andi  x19, x1, 6
  slli  x20, x1, 2
  srli  x21, x1, 1
  srai  x22, x13, 2
  lui   x23, 0x12345
  auipc x24, 0
  addi  x0, x0, 7

  # Keep IMEM defined until the fixed Phase 1 watchdog expires.
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
