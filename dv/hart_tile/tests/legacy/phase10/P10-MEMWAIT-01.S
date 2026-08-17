/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# Phase 10 directed memory wait-state test.
#
# The TB runs this image with IMEM/DMEM READ_LATENCY parameters greater than 1.
# The program performs a store followed by a load-use dependency so the
# pipeline must stall cleanly across both instruction-fetch and data-load
# response delays.

addi x1, x0, 0x100
addi x2, x0, 0x02a
sw   x2, 0(x1)
lw   x3, 0(x1)
add  x4, x3, x2
addi x5, x4, 1

done:
jal  x0, done
