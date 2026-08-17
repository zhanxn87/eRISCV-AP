/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# HPM control-flow event verification:
# BRANCH_RETIRED = 2, BRANCH_TAKEN = 1, CONTROL_TRANSFER_RETIRED = 1.

  .option norvc
  .globl _start
_start:
  csrw  mhpmevent3, x0
  csrw  mhpmevent4, x0
  csrw  mhpmevent5, x0
  csrw  mhpmcounter3, x0
  csrw  mhpmcounter4, x0
  csrw  mhpmcounter5, x0

  li    x1, 3
  csrw  mhpmevent3, x1
  li    x1, 4
  csrw  mhpmevent4, x1
  li    x1, 5
  csrw  mhpmevent5, x1

  beq   x0, x0, 1f
  nop
1:
  bne   x0, x0, 2f
  nop
2:
  jal   x0, 3f
  nop
3:
  csrw  mhpmevent3, x0
  csrw  mhpmevent4, x0
  csrw  mhpmevent5, x0
  csrr  x2, mhpmcounter3
  li    x3, 2
  bne   x2, x3, fail
  csrr  x2, mhpmcounter4
  li    x3, 1
  bne   x2, x3, fail
  csrr  x2, mhpmcounter5
  li    x3, 1
  bne   x2, x3, fail

  li    x28, 1
  jal   x0, done
fail:
  li    x28, 0
done:
  jal   x0, done
