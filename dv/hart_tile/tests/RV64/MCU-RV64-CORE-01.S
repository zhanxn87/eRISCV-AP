# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

# Focused RV64 integer-core smoke: XLEN datapath, 64-bit D-bus accesses,
# RV64 *W operations, RV64M, and the RV64C-only decompression encodings.

.section .text
.option rvc
.globl _start
_start:
  lui   x1, 0x1
  slli  x1, x1, 20             # x1 = 0x0000000100000000
  addi  x1, x1, 7              # x1 = 0x0000000100000007
  addiw x2, x1, -1             # x2 = 6

  sd    x1, 0(x0)
  ld    x3, 0(x0)
  sw    x1, 8(x0)
  lwu   x4, 8(x0)
  lw    x5, 8(x0)

  addi  x6, x0, -1
  addiw x7, x6, 0
  slliw x8, x7, 1
  mulw  x9, x8, x2
  mul   x10, x1, x2

  addi  sp, x0, 0
  c.addiw a2, 1
  c.addw  a2, a2
  c.sdsp  a2, 16(sp)
  c.ldsp  a3, 16(sp)

1:
  j 1b
