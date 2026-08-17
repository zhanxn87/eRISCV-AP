/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# MCU HPM event-counter test.
# Fixed event mapping:
#   mhpmcounter3 = load-use stalls
#   mhpmcounter4 = branch/jump control flushes
#   mhpmcounter5 = trap entries
#   mhpmcounter6 = data-memory wait stalls
#
# MCU maps executable IMEM at 0x0000_0000 and DMEM at 0x0004_0000.

  addi  x31, x0, 0x80
  csrrw x0,  mtvec, x31
  csrrw x0,  mhpmcounter3, x0
  csrrw x0,  mhpmcounter4, x0
  csrrw x0,  mhpmcounter5, x0
  csrrw x0,  mhpmcounter6, x0

  lui   x1,  0x40
  lw    x1,  0(x1)
  addi  x2,  x1, 1

  beq   x0, x0, 1f
  addi  x3, x0, 99
1: addi  x3, x0, 3

  ecall
  addi  x4, x0, 4

  csrrs x10, mhpmcounter3, x0
  csrrs x11, mhpmcounter4, x0
  csrrs x12, mhpmcounter5, x0
  csrrs x13, mhpmcounter6, x0

done:
  jal   x0, done

  # NOP padding until 0x80.
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop

handler:
  csrrs x5, mepc, x0
  addi  x5, x5, 4
  csrrw x0, mepc, x5
  mret
