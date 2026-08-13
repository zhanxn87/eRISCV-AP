/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# Phase 5 CSR/trap bring-up test.
# The trap handler starts at mtvec=0x80.

  addi  x1, x0, 0x80
  csrrw x5, mtvec, x1
  ecall
  addi  x9, x0, 9
  addi  x10, x0, 10
done:
  jal   x0, done

  # NOP padding until 0x80.
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

handler:
  csrrs x6, mcause, x0
  csrrs x7, mepc, x0
  addi  x8, x7, 4
  csrrw x0, mepc, x8
  mret
