/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# WFI must hold younger execution until a pending machine external interrupt wakes it.

  .section .text
  .globl _start
  .option norvc
_start:
  li    x1, 0x100
  csrw  mtvec, x1
  # Count WFI wait cycles without constraining their implementation-dependent
  # total.  The controlled external interrupt below must make this nonzero.
  csrw  mhpmevent6, x0
  csrw  mhpmcounter6, x0
  li    x1, 14
  csrw  mhpmevent6, x1
  li    x1, 0x800
  csrs  mie, x1
  li    x1, 8
  csrs  mstatus, x1

  wfi
  addi  x10, x0, 1
  csrw  mhpmevent6, x0
  csrr  x27, mhpmcounter6
  sltu  x27, x0, x27
  li    x24, 1
wfi_done:
  jal   x0, wfi_done

  .org 0x100
handler:
  csrr  x2, mcause
  addi  x25, x10, 0
  li    x26, 1
  mret
