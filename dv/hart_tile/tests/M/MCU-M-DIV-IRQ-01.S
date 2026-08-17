/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# MCU-M-DIV-IRQ-01: precise external interrupt at a multi-cycle DIV boundary.
#
# The TB raises MEIP only after it observes muldiv_busy.  The handler checks
# that MEPC names the interrupted DIV, masks the level source, then MRET
# restarts and retires the DIV exactly once.  x28 = 1 denotes PASS.

  .globl _start
_start:
  la    x31, handler
  csrw  mtvec, x31

  li    x2, 0x800
  csrs  mie, x2
  li    x2, 8
  csrs  mstatus, x2
  li    x27, 0

  li    x10, 1000
  li    x11, 7
interrupt_div:
  div   x14, x10, x11           # 142
  addi  x15, x14, 1             # dependent consumer: 143
  li    x1, 143
  bne   x15, x1, fail
  li    x1, 1
  bne   x27, x1, fail

  li    x28, 1
  jal   x0, done

fail:
  li    x28, 0

done:
  jal   x0, done

  .balign 256
handler:
  csrr  x29, mepc
  csrr  x30, mcause
  li    x2, 0x8000000b
  bne   x30, x2, fail
  li    x2, 0x800
  csrc  mie, x2
  la    x2, interrupt_div
  bne   x29, x2, fail
  li    x27, 1
  mret
