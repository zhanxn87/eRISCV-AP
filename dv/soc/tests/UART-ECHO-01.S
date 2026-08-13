/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# UART RX-to-TX directed test shared with M0.

.globl _start
_start:

lui  x1, 0x40000
addi x2, x0, 8
sw   x2, 12(x1)
addi x2, x0, 3
sw   x2, 16(x1)

poll_rx:
lw   x3, 8(x1)
andi x3, x3, 2
beq  x3, x0, poll_rx
lw   x5, 4(x1)

poll_tx:
lw   x3, 8(x1)
andi x3, x3, 1
beq  x3, x0, poll_tx
sw   x5, 0(x1)

done:
jal  x0, done
