/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

/* RV64I ALU, OP-IMM-32/OP-32, conditional branches, JAL, and JALR. */

  .section .text
  .option rvc
  .globl _start
_start:
  lui   x1, 0x1
  slli  x1, x1, 20             /* 0x0000000100000000 */
  addi  x1, x1, 5
  addi  x26, x0, 1
  slli  x26, x26, 32           /* RV64 shamt[5] coverage. */
  addi  x2, x0, -1
  addi  x7, x0, 4

  add   x3, x1, x2
  sub   x4, x0, x1
  sll   x5, x1, x7
  srl   x6, x2, x7
  sra   x8, x2, x7
  slt   x9, x2, x1
  sltu  x10, x1, x2
  xor   x11, x1, x2
  or    x12, x1, x2
  and   x13, x1, x2
  slli  x14, x1, 1
  srli  x15, x2, 63
  srai  x16, x2, 63
  addiw x17, x2, 2
  slliw x18, x2, 1
  srliw x19, x2, 31
  sraiw x20, x2, 31

  addi  x21, x0, 0
  beq   x1, x1, 1f
  j     fail
1:
  bne   x1, x2, 2f
  j     fail
2:
  blt   x2, x1, 3f
  j     fail
3:
  bge   x1, x2, 4f
  j     fail
4:
  bltu  x1, x2, 5f
  j     fail
5:
  bgeu  x2, x1, 6f
  j     fail
6:
  blt   x1, x2, fail
  bge   x2, x1, fail
  bltu  x2, x1, fail
  bgeu  x1, x2, fail

  jal   x22, 7f
  j     fail
7:
  beq   x22, x0, fail
  la    x23, 8f
  jalr  x24, x23, 0
  j     fail
8:
  beq   x24, x0, fail
  j     done

fail:
  addi  x21, x0, -1
done:
  j     done
