/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# Phase 7 CSR dependency stress test.
# Covers back-to-back CSR write/read, CSRRS set, and CSRRC clear dependencies.

  addi  x1,  x0, 0x80
  csrrw x2,  mtvec, x1
  csrrs x3,  mtvec, x0

  addi  x6,  x0, 8
  csrrw x0,  mstatus, x6
  csrrs x7,  mstatus, x0

  addi  x8,  x0, 3
  csrrs x0,  mstatus, x8
  csrrs x9,  mstatus, x0

  addi  x10, x0, 2
  csrrc x0,  mstatus, x10
  csrrs x11, mstatus, x0
done:
  jal   x0, done
