/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# M2 compressed-control prediction guard.
#
# C.BEQZ/C.BNEZ use the normalized BTFNT path. C.J/C.JAL redirect in ID;
# C.JALR remains intentionally out of scope because its target is indirect.

  .option rvc
  .globl _start
_start:
  c.li    x8, 2
c_back_taken:
  c.addi  x8, -1
  c.bnez  x8, c_back_taken

  c.li    x9, 0
  c.li    x8, 1
c_back_not_taken_target:
  c.addi  x9, 1
  c.beqz  x8, c_back_not_taken_target

  c.li    x8, 0
  c.beqz  x8, c_forward_taken_target
  c.li    x10, 1
c_forward_taken_target:
  c.li    x10, 2

  c.bnez  x8, c_forward_not_taken_target
  c.li    x11, 3
  c.j     c_after_forward
c_forward_not_taken_target:
  c.li    x11, 4

c_after_forward:
  c.j     c_j_target
  c.li    x12, 1
c_j_target:
  c.li    x12, 2
  c.jal   c_jal_target
  c.li    x13, 1
c_jal_target:
  c.li    x13, 2
done:
  c.j     done
