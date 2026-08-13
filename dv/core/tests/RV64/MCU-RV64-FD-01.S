/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

/* RV64F/D core regression: FP64 arithmetic/LSU, integer conversions, F2F,
 * and FP32 NaN-boxed execution on the shared 64-bit FPR file. */

  .section .text
  .option norvc
  .globl _start
_start:
  li      x31, 0x0000000000006000
  csrrs   x0, mstatus, x31

  li      x1, 0x3ff0000000000000       /* 1.0 */
  li      x2, 0x4000000000000000       /* 2.0 */
  fmv.d.x f1, x1
  fmv.d.x f2, x2
  fadd.d  f3, f1, f2                   /* 3.0 */
  fsd     f3, 0(x0)
  fld     f4, 0(x0)
  fmul.d  f5, f4, f2                   /* 6.0 */
  fmv.x.d x3, f5
  fdiv.d  f20, f5, f2                  /* 3.0 */
  fmv.x.d x21, f20
  fmul.d  f21, f2, f2                  /* 4.0 */
  fsqrt.d f22, f21                     /* 2.0 */
  fmv.x.d x22, f22
  fmadd.d f6, f1, f2, f3               /* 5.0 */
  fmv.x.d x8, f6
  fnmsub.d f7, f2, f2, f1              /* -5.0 */
  fmv.x.d x9, f7
  fnmadd.d f8, f2, f2, f1              /* -3.0 */
  fmv.x.d x10, f8

  li       x4, -7
  fcvt.d.l f9, x4
  fcvt.l.d x5, f9
  li       x6, 0x0000000100000001
  fcvt.d.lu f10, x6
  fcvt.lu.d x7, f10
  fcvt.w.d x17, f3

  fcvt.s.d f11, f3
  fmv.x.w  x11, f11
  fcvt.d.s f12, f11
  fmv.x.d  x12, f12
  li        x18, 0x80000000
  fmv.w.x  f13, x18
  fadd.s   f14, f13, f13               /* -0.0? F13 is -0.0 bit pattern */
  fmv.x.w  x19, f14
  li        x20, 0x3f800000
  fmv.w.x  f15, x20
  fadd.s   f16, f15, f15               /* 2.0 */
  fsw      f16, 8(x0)
  flw      f17, 8(x0)
  fadd.s   f18, f17, f15               /* 3.0 */
  fmv.x.w  x13, f16
  fmv.x.w  x14, f18
  fsgnj.d  f19, f1, f2
  fmv.x.d  x15, f19
  feq.d     x16, f3, f4

done:
  j done
