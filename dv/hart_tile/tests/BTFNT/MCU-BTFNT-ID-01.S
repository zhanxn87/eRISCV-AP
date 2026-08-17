/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# M2 ID-stage BTFNT predictor guard.
#
# Native backward branches predict taken; native forward branches predict not
# taken. Exercise the two correct-prediction paths and both EX corrections.
# Wrong-path ADDIs must not retire.

  .option norvc
  .globl _start
_start:
  li    x3, 2
back_taken:
  addi  x3, x3, -1
  bne   x3, x0, back_taken

  li    x4, 0
  li    x1, 1
back_not_taken_target:
  addi  x4, x4, 1
  beq   x0, x1, back_not_taken_target

  beq   x0, x0, forward_taken_target
  li    x5, 1
forward_taken_target:
  li    x5, 2

  bne   x0, x0, forward_not_taken_target
  li    x6, 3
  jal   x0, checks
forward_not_taken_target:
  li    x6, 4

checks:
  li    x28, 1
  bne   x3, x0, fail
  li    x7, 1
  bne   x4, x7, fail
  li    x7, 2
  bne   x5, x7, fail
  li    x7, 3
  bne   x6, x7, fail
  jal   x0, done

fail:
  li    x28, 0
done:
  jal   x0, done
