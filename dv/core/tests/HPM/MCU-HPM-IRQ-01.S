/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# MCU-HPM-IRQ-01: exact INTERRUPT_TAKEN HPM event.
#
# The test uses the writable machine-software interrupt (MSIP) pending bit,
# not a cycle-timed testbench pulse.  The handler clears MSIP before MRET,
# which makes one accepted interrupt and one counter increment an architectural
# invariant of the test.

  .section .text
  .globl _start
  .option norvc
_start:
  li    x31, 0x200
  csrw  mtvec, x31

  csrw  mhpmevent5, x0
  csrw  mhpmcounter5, x0
  li    x1, 7
  csrw  mhpmevent5, x1

  # Raise and enable MSIP.  MSTATUS.MIE becomes visible after this CSR
  # instruction, so the following nop is the interrupted instruction.
  li    x1, 8
  csrs  mie, x1
  csrs  mip, x1
  csrs  mstatus, x1
  nop
after_interrupt:
  csrw  mhpmevent5, x0
  li    x3, 1
  bne   x26, x3, fail
  csrr  x2, mhpmcounter5
  bne   x2, x3, fail

  li    x28, 1
  jal   x0, done
fail:
  li    x28, 0
done:
  jal   x0, done

  .org 0x200
interrupt_handler:
  csrr  x1, mcause
  li    x2, 0x80000003
  bne   x1, x2, handler_bad
  li    x26, 1
  jal   x0, clear_msip
handler_bad:
  li    x26, 0
clear_msip:
  li    x2, 8
  csrc  mip, x2
  mret
