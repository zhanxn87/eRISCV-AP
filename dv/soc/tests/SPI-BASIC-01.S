/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# EDU RV32I SoC SPI0 basic directed test.
#
# The program configures SPI0 as a mode-0 MSB-first master, selects SS0,
# transmits 0xa5 on MOSI, polls STATUS.done, and reads the MISO byte into x10.
# The TB models an external SPI slave, checks MOSI, and drives MISO=0x3c.

lui  x1, 0x40030

addi x2, x0, 2
sw   x2, 0x0c(x1)
addi x2, x0, 0x0e
sw   x2, 0x14(x1)
addi x2, x0, 1
sw   x2, 0x10(x1)
addi x2, x0, 0x0a5
sw   x2, 0x00(x1)

poll:
lw   x3, 0x08(x1)
andi x4, x3, 4
beq  x4, x0, poll

lw   x10, 0x04(x1)
lw   x11, 0x08(x1)

done:
jal  x0, done
