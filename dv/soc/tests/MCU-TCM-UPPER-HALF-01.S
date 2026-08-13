/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# eRISCV-M2 upper-half TCM capacity test.
#
# The image starts at 0x1001_0000, proving instruction fetch in the second
# 64 KiB of the 128 KiB ITCM.  It then stores and loads two distinct words
# within the second 64 KiB of DTCM.

  .section .text
  .globl _start
  .option norvc
_start:
  lui  x1, 0x11010             # 0x1101_0000, DTCM upper half
  li   x2, 0x13579bdf
  sw   x2, 0(x1)
  lw   x3, 0(x1)

  lui  x4, 0x1101f             # 0x1101_f000, still within DTCM
  li   x5, 0x2468ace0
  sw   x5, 0(x4)
  lw   x6, 0(x4)

  add  x24, x3, x0
  add  x25, x6, x0

done:
  jal  x0, done
