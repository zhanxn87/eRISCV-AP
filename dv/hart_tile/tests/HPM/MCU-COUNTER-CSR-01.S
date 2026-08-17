/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# Zicntr/Zihpm CSR contract: four 64-bit programmable HPM counters.

  .globl _start
_start:
  li    x1, -1
  csrw  mcountinhibit, x1
  csrr  x10, mcountinhibit

  li    x1, 0x11223344
  csrw  mhpmcounter3h, x1
  csrr  x11, mhpmcounter3h

  li    x1, 4
  csrw  mhpmevent3, x1
  csrr  x12, mhpmevent3

  li    x1, 1
  csrw  mcountinhibit, x1
  csrr  x14, mcycle
  nop
  nop
  csrr  x15, mcycle
  bne   x14, x15, fail

  csrw  mcountinhibit, x0
  csrr  x16, mcycle
  nop
  nop
  csrr  x17, mcycle
  bge   x16, x17, fail

  li    x24, 1
  jal   x0, done

fail:
  addi  x24, x0, 0

done:
  jal   x0, done
