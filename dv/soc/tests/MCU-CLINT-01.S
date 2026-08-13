/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

  .section .text
  .globl _start
  .option rvc
_start:
  li x5, 0x02000000
  # T1: MTIME low read. The value is asynchronous to the program, so only
  # the zero-bus-error oracle checks this access; do not include it in x24.
  li x6, 0xbff8
  add x6, x5, x6
  lw x23, 0(x6)
  # T2: mtimecmp r/w
  li x7, 0xdeadbeef
  li x8, 0x4000
  add x8, x5, x8
  sw x7, 0(x8)
  lw x9, 0(x8)
  sub x25, x7, x9
  # T3: MSIP set/clear
  sw x0, 0(x5)
  lw x26, 0(x5)
  andi x26, x26, 1
  li x10, 1
  sw x10, 0(x5)
  lw x11, 0(x5)
  andi x27, x11, 1
  addi x27, x27, -1
  sw x0, 0(x5)
  lw x28, 0(x5)
  andi x28, x28, 1
  add x24, x25, x26
  add x24, x24, x27
  add x24, x24, x28
pass: j .
fail: li x24, -1; j .
