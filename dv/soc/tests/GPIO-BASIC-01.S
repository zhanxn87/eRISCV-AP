/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# EDU RV32I SoC APB GPIO directed test.
#
# The program configures GPIO0 low eight pins as outputs, writes an output
# value, then reads back OUT, DIR, and the external input sample provided by
# the TB on gpio_i.

lui  x1, 0x40010
addi x2, x0, 0xff
sw   x2, 0x008(x1)
addi x3, x0, 0x3c
sw   x3, 0x000(x1)
lw   x5, 0x000(x1)
lw   x6, 0x008(x1)
lw   x7, 0x004(x1)

done:
jal  x0, done
