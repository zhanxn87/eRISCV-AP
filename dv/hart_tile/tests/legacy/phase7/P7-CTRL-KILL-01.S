/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# Phase 7 control/trap kill stress test.
# Covers taken-branch wrong-path store kill and ECALL trap redirect flushing a
# younger store. The handler skips that younger store by advancing MEPC by 8.

  addi  x1, x0, 0
  addi  x2, x0, 0x80
  csrrw x0, mtvec, x2
  addi  x3, x0, 0x55
  sw    x3, 12(x1)

  addi  x9, x0, 1
  beq   x9, x9, branch_ok
  sw    x0, 12(x1)
branch_ok:
  ecall
  sw    x0, 12(x1)
  addi  x4, x0, 44
  lw    x5, 12(x1)
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

handler:
  csrrs x6, mcause, x0
  csrrs x7, mepc, x0
  addi  x8, x7, 8
  csrrw x0, mepc, x8
  mret
