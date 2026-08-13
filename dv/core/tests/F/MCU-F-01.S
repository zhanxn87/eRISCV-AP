/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# RV32F smoke: FS/FCSR, exact FP WB, FLW/FSW, and a load-to-FP hazard.
  lui   x6, 0x6
  csrrs x0, mstatus, x6
  lui   x1, 0x3f800
  lui   x2, 0x40000
  fmv.w.x f1, x1
  fmv.w.x f2, x2
  fadd.s  f3, f1, f2
  fsw     f3, 0(x0)
  flw     f4, 0(x0)
  fadd.s  f5, f4, f1
  fmv.x.w x3, f5
  # Chained FMA/DIV/MUL/SUB verifies that a completed FPR writer is held
  # until a dependent FP reader captures its source operands in ID.
  fmadd.s f6, f1, f2, f5
  fdiv.s  f7, f6, f2
  fmul.s  f8, f7, f2
  fsub.s  f9, f8, f5
  fmv.x.w x8, f9
  fle.s   x9, f1, f2
  flt.s   x10, f1, f2
  feq.s   x11, f1, f1
  fsgnjn.s f10, f1, f2
  fmv.x.w x12, f10
  flt.s   x13, f1, f2
  bnez    x13, 1f
  li      x14, 0
  j       2f
1:
  li      x14, 1
2:
  # minver's pivot path compares a negative candidate against +0.0 before
  # branching.  Cover both mixed-sign orderings explicitly.
  fsub.s   f12, f1, f1
  fsgnjn.s f11, f1, f1
  fle.s    x15, f12, f11
  flt.s    x16, f11, f12
  // The minver epsilon check consumes the negated candidate as rs1.
  fsgnjn.s f13, f1, f1
  flt.s    x19, f13, f12
  # minver stores each quotient immediately.  Verify the FPR-to-store path
  # observes an FDIV completion rather than a stale source register value.
  fdiv.s   f13, f2, f1
  fsw      f13, 4(x0)
  flw      f14, 4(x0)
  fmv.x.w  x17, f14
  # minver's row elimination is compiled as FNMSUB.S followed by FSW.
  fnmsub.s f15, f1, f2, f5
  fmv.x.w  x18, f15
  csrr    x4, fflags
  csrr    x5, mstatus
  csrr    x7, misa
  nop
  nop
  nop
  nop
