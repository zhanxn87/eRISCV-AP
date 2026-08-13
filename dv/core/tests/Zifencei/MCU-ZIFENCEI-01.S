/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# eRISCV MCU Zifencei (fence.i) directed test.
# rv32ic_zicsr_zifencei, ilp32 ABI.

  .section .text
  .globl _start
  .option rvc
_start:
  # Test 1: fence.i should execute without trapping
  fence.i
  c.nop

  # Test 2: fence.i after a regular DMEM store
  li x5, 0x11000000
  li x6, 0x00000013      # nop encoding
  sw x6, 0(x5)
  fence.i
  lw x7, 0(x5)
  sub x31, x7, x6
  c.nop

  # Test 3: fence.i in a loop (stress)
  li x7, 3
1:
  fence.i
  c.addi x7, -1
  bnez x7, 1b            # assembler can auto-compress this

  # Test 4: fence.i followed by jump
  fence.i
  c.j 2f
  c.nop
2:
  fence.i

  # Result: x31 = 0 means all tests passed
pass:
  j .

fail:
  li x31, -1
  j .
