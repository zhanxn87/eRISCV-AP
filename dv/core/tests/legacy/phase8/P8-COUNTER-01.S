/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# Phase 8 counter CSR test.
# Checks writable mcycle/minstret and cycle/instret aliases.
# M2 observes minstret at non-trapping EX completion, so the first read
# includes that CSR instruction and returns four after three integer ops.

  csrrw x0, minstret, x0
  csrrw x0, mcycle,   x0
  addi  x1, x0, 1
  addi  x2, x0, 2
  add   x5, x1, x2
  csrrs x3, minstret, x0
  csrrs x4, mcycle,   x0
  csrrw x0, minstret, x0
  addi  x6, x0, 6
  csrrs x7, minstret, x0
  csrrs x8, instret,  x0
  csrrs x9, cycle,    x0
done:
  jal   x0, done
