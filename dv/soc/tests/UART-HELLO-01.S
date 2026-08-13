/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# EDU RV32I SoC APB UART Hello World directed test.
#
# The program configures UART0 at 0x4000_0000 and transmits "Hello World"
# through the real UART TX pin. The TB decodes uart_tx_o and checks the byte
# sequence with the expected UART oracle.

lui  x1, 0x40000
addi x2, x0, 8
sw   x2, 12(x1)
addi x2, x0, 3
sw   x2, 16(x1)

poll_tx_H:
lw   x3, 8(x1)
andi x3, x3, 1
beq  x3, x0, poll_tx_H
addi x2, x0, 0x48
sw   x2, 0(x1)

poll_tx_e:
lw   x3, 8(x1)
andi x3, x3, 1
beq  x3, x0, poll_tx_e
addi x2, x0, 0x65
sw   x2, 0(x1)

poll_tx_l0:
lw   x3, 8(x1)
andi x3, x3, 1
beq  x3, x0, poll_tx_l0
addi x2, x0, 0x6c
sw   x2, 0(x1)

poll_tx_l1:
lw   x3, 8(x1)
andi x3, x3, 1
beq  x3, x0, poll_tx_l1
addi x2, x0, 0x6c
sw   x2, 0(x1)

poll_tx_o0:
lw   x3, 8(x1)
andi x3, x3, 1
beq  x3, x0, poll_tx_o0
addi x2, x0, 0x6f
sw   x2, 0(x1)

poll_tx_space:
lw   x3, 8(x1)
andi x3, x3, 1
beq  x3, x0, poll_tx_space
addi x2, x0, 0x20
sw   x2, 0(x1)

poll_tx_W:
lw   x3, 8(x1)
andi x3, x3, 1
beq  x3, x0, poll_tx_W
addi x2, x0, 0x57
sw   x2, 0(x1)

poll_tx_o1:
lw   x3, 8(x1)
andi x3, x3, 1
beq  x3, x0, poll_tx_o1
addi x2, x0, 0x6f
sw   x2, 0(x1)

poll_tx_r:
lw   x3, 8(x1)
andi x3, x3, 1
beq  x3, x0, poll_tx_r
addi x2, x0, 0x72
sw   x2, 0(x1)

poll_tx_l2:
lw   x3, 8(x1)
andi x3, x3, 1
beq  x3, x0, poll_tx_l2
addi x2, x0, 0x6c
sw   x2, 0(x1)

poll_tx_d:
lw   x3, 8(x1)
andi x3, x3, 1
beq  x3, x0, poll_tx_d
addi x2, x0, 0x64
sw   x2, 0(x1)

addi x5, x0, 11

done:
jal  x0, done
