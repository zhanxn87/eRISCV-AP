/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# Phase 7 forwarding stress test.
# Covers EX/MEM priority over MEM/WB, dual-operand forwarding, branch operand
# forwarding, JALR base forwarding, link writeback, and x0 suppression.

  addi x1,  x0, 1
  addi x1,  x1, 2
  addi x2,  x1, 4
  addi x1,  x1, 5
  add  x3,  x1, x2
  add  x4,  x3, x1
  addi x5,  x4, -3
  addi x0,  x5, 99
  add  x6,  x0, x5

  addi x7,  x0, 11
  addi x8,  x7, 0
  beq  x8,  x7, branch_ok
  addi x9,  x0, 99
branch_ok:
  addi x9,  x0, 9

  addi x12, x0, 0x48
  jalr x13, x12, 0
  addi x14, x0, 99
  addi x15, x0, 99
jalr_target:
  addi x14, x0, 14
  addi x15, x0, 15
  add  x17, x14, x15
done:
  jal  x0, done
