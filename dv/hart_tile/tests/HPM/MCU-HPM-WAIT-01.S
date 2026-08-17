/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# MCU-HPM-WAIT-01: prove the four implemented wait/stall HPM qualifiers.
#
# The core runner supplies deterministic non-unit IMEM and DMEM latencies.
# These events are cycle counters, so this test asserts each count is nonzero
# instead of freezing a microarchitecture-specific total.  The load-use result
# remains a functional oracle for the dependent instruction.

  .section .text
  .globl _start
  .option norvc
_start:
  csrw  mhpmevent3, x0
  csrw  mhpmevent4, x0
  csrw  mhpmevent5, x0
  csrw  mhpmevent6, x0
  csrw  mhpmcounter3, x0
  csrw  mhpmcounter4, x0
  csrw  mhpmcounter5, x0
  csrw  mhpmcounter6, x0

  li    x6, 8
  csrw  mhpmevent3, x6          # IFETCH_WAIT_CYCLES
  li    x6, 9
  csrw  mhpmevent4, x6          # DATA_WAIT_CYCLES
  li    x6, 10
  csrw  mhpmevent5, x6          # PIPELINE_STALL_CYCLES
  li    x6, 11
  csrw  mhpmevent6, x6          # LOAD_USE_STALL_CYCLES

  li    x1, 0x100
  li    x2, 0x2a
  sw    x2, 0(x1)
  lw    x3, 0(x1)
  add   x4, x3, x2
  addi  x5, x4, 1

  csrw  mhpmevent3, x0
  csrw  mhpmevent4, x0
  csrw  mhpmevent5, x0
  csrw  mhpmevent6, x0
  csrr  x6, mhpmcounter3
  sltu  x24, x0, x6
  csrr  x6, mhpmcounter4
  sltu  x25, x0, x6
  csrr  x6, mhpmcounter5
  sltu  x26, x0, x6
  csrr  x6, mhpmcounter6
  sltu  x27, x0, x6

  li    x28, 1
done:
  jal   x0, done
