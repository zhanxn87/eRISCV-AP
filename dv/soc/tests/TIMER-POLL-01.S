/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# EDU RV32I SoC APB timer polling directed test.
#
# The program configures TIMER0 at 0x4002_0000, enables counting, polls the
# sticky STATUS.expired bit, then records the observed status and a completion
# marker in registers checked by the TB.

lui  x1, 0x40020
addi x2, x0, 20
sw   x2, 0x008(x1)
addi x2, x0, 1
sw   x2, 0x000(x1)

poll_timer:
lw   x3, 0x00c(x1)
andi x3, x3, 1
beq  x3, x0, poll_timer

lw   x5, 0x00c(x1)
addi x6, x0, 1

done:
jal  x0, done
