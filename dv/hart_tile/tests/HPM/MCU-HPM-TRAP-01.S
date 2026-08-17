/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# MCU-HPM-TRAP-01: exact BRANCH_TAKEN and EXCEPTION_TAKEN HPM events.
#
# Each selector is enabled only for its one deterministic stimulus, then set
# back to EVENT_NONE before the counter is inspected.  This deliberately keeps
# the test's own control flow out of the measured interval.

  .section .text
  .globl _start
  .option norvc
_start:
  li    x31, 0x200
  csrw  mtvec, x31

  # BRANCH_TAKEN: one known-taken conditional branch.
  csrw  mhpmevent3, x0
  csrw  mhpmcounter3, x0
  li    x1, 4
  csrw  mhpmevent3, x1
  beq   x0, x0, branch_taken
  jal   x0, fail
branch_taken:
  csrw  mhpmevent3, x0
  csrr  x2, mhpmcounter3
  li    x3, 1
  bne   x2, x3, fail

  # EXCEPTION_TAKEN: one ECALL.  The handler checks its precise cause and
  # advances mepc so normal execution resumes at after_ecall.
  csrw  mhpmevent4, x0
  csrw  mhpmcounter4, x0
  li    x1, 6
  csrw  mhpmevent4, x1
  ecall
after_ecall:
  csrw  mhpmevent4, x0
  li    x3, 1
  bne   x27, x3, fail
  csrr  x2, mhpmcounter4
  bne   x2, x3, fail

  li    x28, 1
  jal   x0, done

fail:
  li    x28, 0
done:
  jal   x0, done

  .org 0x200
exception_handler:
  csrr  x1, mcause
  li    x2, 11
  bne   x1, x2, handler_bad
  li    x27, 1
  jal   x0, handler_resume
handler_bad:
  li    x27, 0
handler_resume:
  csrr  x1, mepc
  addi  x1, x1, 4
  csrw  mepc, x1
  mret
