/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# Phase 9 machine external interrupt test.
# TB drives irq_i[11] after MIE and MEIE are enabled.

  addi  x1, x0, 0x80
  csrrw x0, mtvec, x1
  addi  x1, x0, 1
  slli  x1, x1, 11
  csrrw x0, mie, x1
  addi  x1, x0, 8
  csrrw x0, mstatus, x1
  addi  x5, x0, 5
  addi  x6, x0, 6
  addi  x7, x0, 7
  addi  x8, x0, 8
done:
  jal   x0, done

  # NOP padding until 0x80.

handler:
  csrrs x10, mcause, x0
  csrrs x11, mepc, x0
  csrrs x12, mip, x0
  csrrs x13, mstatus, x0
  addi  x14, x0, 1
  mret
