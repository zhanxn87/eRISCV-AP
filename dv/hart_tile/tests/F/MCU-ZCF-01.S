/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# RV32Zcf smoke: C.FLW, C.FSW, C.FLWSP, and C.FSWSP.
# x31 returns the final loaded binary32 value.

.option rvc
.text
.globl _start
_start:
  li x6, 0x6000
  csrrs x0, mstatus, x6
  li sp, 0x1000
  mv s0, sp
  li a0, 0x3f800000
  fmv.w.x f8, a0
  c.fsw f8, 0(s0)
  c.flw f9, 0(s0)
  c.fswsp f9, 4(sp)
  c.flwsp f10, 4(sp)
  fmv.x.w x31, f10
1: j 1b
