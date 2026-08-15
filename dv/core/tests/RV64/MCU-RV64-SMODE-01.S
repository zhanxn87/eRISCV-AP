# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

# RV64GC S-mode privilege baseline: enter U with MRET, delegate U-ECALL to
# S-mode, verify SCAUSE/SEPC, advance SEPC, and return with SRET.
.section .text
.option norvc
.globl _start
_start:
  addi  t0, x0, 0x100
  csrw  stvec, t0
  csrw  medeleg, t0              # Delegate ECALL-from-U (cause 8).
  addi  t0, x0, 0x80
  csrw  mepc, t0
  csrw  mstatus, x0              # MPP=U and MIE=0.
  mret

.org 0x80
user_entry:
  lui   a0, 0x1
  addi  a0, a0, 0x111            # a0 = 0x1111, preserved through trap.
  ecall
user_after_ecall:
  lui   a1, 0x2
  addi  a1, a1, 0x222            # a1 = 0x2222 proves SRET redirect.
1:
  j     1b

.org 0x100
supervisor_handler:
  csrr  t2, scause
  addi  t3, x0, 8
  bne   t2, t3, fail
  csrr  t2, sepc
  addi  t3, x0, 0x88             # ECALL at user_entry + 8.
  bne   t2, t3, fail
  addi  t2, t2, 4
  csrw  sepc, t2
  lui   a2, 0x3
  addi  a2, a2, 0x333            # a2 = 0x3333 proves S-mode execution.
  sret

fail:
  lui   a0, 0xe
  addi  a0, a0, -339             # a0 = 0xdead; does not meet oracle.
2:
  j     2b
