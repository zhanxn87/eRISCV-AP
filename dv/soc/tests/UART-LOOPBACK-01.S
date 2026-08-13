/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# EDU RV32I SoC APB UART directed test.
#
# The program configures UART0 at 0x4000_0000, transmits 0x55, then polls for
# one received byte injected by the TB. The expected register oracle checks the
# received value in x5.

lui  x1, 0x40000
addi x2, x0, 8
sw   x2, 12(x1)
addi x2, x0, 3
sw   x2, 16(x1)

poll_tx:
lw   x3, 8(x1)
andi x3, x3, 1
beq  x3, x0, poll_tx

addi x2, x0, 0x55
sw   x2, 0(x1)

poll_rx:
lw   x3, 8(x1)
andi x3, x3, 2
beq  x3, x0, poll_rx

lw   x5, 4(x1)

done:
jal  x0, done
