/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

/* RV64C: a raw 32-bit instruction at PC[1]=1 plus RV64-only C operations. */

  .section .text
  .option rvc
  .globl _start
_start:
  .p2align 2
  c.nop
  .option push
  .option norvc
  addi  x1, x0, 1              /* PC[1]=1: crosses an IMEM 32-bit word. */
  addi  x1, x1, 1
  .option pop
  c.addi  x1, 1
  c.slli  x1, 1

  c.li    x8, 0
  c.beqz  x8, 1f
  c.li    x9, -1
1:
  c.li    x9, 1
  c.bnez  x9, 2f
  c.li    x10, -1
2:
  c.li    x10, 3
  c.addw  x10, x10
  c.addiw x10, 1
  c.mv    x11, x10
  c.sd    x11, 0(x8)
  c.ld    x12, 0(x8)
  c.sw    x11, 8(x8)
  c.lw    x13, 8(x8)
  c.li    sp, 0
  c.swsp  x11, 12(sp)
  c.lwsp  x14, 12(sp)
  c.sdsp  x11, 16(sp)
  c.ldsp  x15, 16(sp)

  la      x16, 3f
  c.jr    x16
  c.li    x17, -1
3:
  la      x16, 4f
  c.jalr  x16
  c.li    x17, -1
4:
  c.j     5f
  c.li    x17, -1
5:
  c.li    x17, 1

done:
  j       done
