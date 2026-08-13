/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# RV32Zicond directed test. rs1 is preserved when the condition does not
# select zero; the final two cases also cover an x0 value operand.
  addi       x1, x0, 0
  addi       x2, x0, 42
  czero.eqz  x3, x2, x1
  czero.eqz  x4, x2, x2
  czero.nez  x5, x2, x1
  czero.nez  x6, x2, x2
  czero.eqz  x7, x0, x1
  czero.nez  x8, x0, x2
  nop
  nop
  nop
  nop
