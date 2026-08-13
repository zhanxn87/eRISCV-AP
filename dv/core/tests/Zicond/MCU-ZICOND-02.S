/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# Zicond dependency and operand-alias coverage. ACT4 consumes each result
# immediately while it also exercises rd=rs1 and rd=rs2 encodings.
  addi       x1, x0, 0
  addi       x2, x0, 42
  czero.eqz  x3, x2, x1
  addi       x4, x3, 1
  czero.nez  x5, x2, x1
  addi       x6, x5, 1

  czero.eqz  x2, x2, x1
  addi       x7, x2, 1
  czero.nez  x1, x2, x1
  addi       x8, x1, 1

  addi       x9, x0, 42
  addi       x10, x0, 0
  czero.eqz  x10, x9, x10
  addi       x11, x10, 1
  czero.nez  x9, x9, x9
  addi       x12, x9, 1

  nop
  nop
  nop
  nop
