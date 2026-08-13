/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# MCU-TIME-CSR-01: correlate time/timeh CSRs with the CLINT MTIME registers.
#
# MTIME is placed just before a low-half rollover.  A bounded instruction
# interval then establishes high-half rollover through both interfaces.  The
# low halves are read sequentially, so they are checked for monotonicity and a
# bounded observation gap rather than false same-cycle equality.

  .section .text
  .globl _start
  .option norvc
_start:
  li    x5, 0x02000000
  li    x6, 0xbffc
  add   x6, x5, x6              # CLINT MTIME high word
  li    x7, 0xbff8
  add   x7, x5, x7              # CLINT MTIME low word

  sw    x0, 0(x6)               # mtime[63:32] = 0
  li    x8, -32
  sw    x8, 0(x7)               # mtime[31:0] = 0xffff_ffe0

  # Cross the rollover without relying on a bus-response cycle count.
  .rept 64
  nop
  .endr

  csrr  x9, timeh
  li    x10, 1
  bne   x9, x10, fail
  lw    x11, 0(x6)
  bne   x11, x10, fail

  csrr  x12, time
  lw    x13, 0(x7)
  bltu  x13, x12, fail
  sub   x14, x13, x12
  li    x15, 64
  bgeu  x14, x15, fail
  csrr  x16, timeh
  bne   x16, x10, fail

  li    x24, 1
done:
  jal   x0, done
fail:
  li    x24, 0
  jal   x0, done
