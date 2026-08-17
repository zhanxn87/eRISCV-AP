/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# Direct JAL early-redirect test.
# The sequential instructions must not execute, and rd receives PC + 4.

  .option norvc
  .globl _start
_start:
  jal   x1, target
  addi  x3, x0, 1
  addi  x3, x0, 2
target:
  addi  x2, x0, 4
  bne   x1, x2, fail
  bne   x3, x0, fail
  li    x28, 1
  jal   x0, done
fail:
  li    x28, 0
done:
  jal   x0, done
