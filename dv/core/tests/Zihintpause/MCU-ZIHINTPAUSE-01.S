/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# eRISCV-M2 Zihintpause directed test.
# The PAUSE hint is legal and has no required architectural effect.

  .section .text
  .globl _start
  .option rvc
_start:
  li x5, 1
  pause
  addi x5, x5, 2
  pause
  li x6, 3
  bne x5, x6, fail
  pause

  # x31 == 0 is the directed-test pass oracle.
  li x31, 0
pass:
  j .

fail:
  li x31, -1
