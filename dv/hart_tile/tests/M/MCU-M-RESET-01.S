/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# MCU-M-RESET-01: M/D post-reset sanity. Writes phase# to DMEM[0x00] for debug.
.globl _start
_start:
  lui   x31, 0x00040            # DMEM base for debug writes

  li    x1, -7
  li    x2, 3

  # Phase 1: MUL
  li    x30, 1; sw x30, 0(x31)
  mul   x3, x1, x2
  li    x4, -21
  bne   x3, x4, fail

  # Phase 2: MULH
  li    x30, 2; sw x30, 0(x31)
  mulh  x3, x1, x2
  li    x4, -1
  bne   x3, x4, fail

  # Phase 3: MULHSU
  li    x30, 3; sw x30, 0(x31)
  mulhsu x3, x1, x2
  li    x4, -1
  bne   x3, x4, fail

  # Phase 4: MULHU
  li    x30, 4; sw x30, 0(x31)
  mulhu x3, x1, x2
  li    x4, 2
  bne   x3, x4, fail

  # Phase 5: DIV
  li    x30, 5; sw x30, 0(x31)
  div   x3, x1, x2
  li    x4, -2
  bne   x3, x4, fail

  # Phase 6: DIVU
  li    x30, 6; sw x30, 0(x31)
  divu  x3, x1, x2
  lui   x4, 0x55555
  addi  x4, x4, 0x553
  bne   x3, x4, fail

  # Phase 7: REM
  li    x30, 7; sw x30, 0(x31)
  rem   x3, x1, x2
  li    x4, -1
  bne   x3, x4, fail

  # Phase 8: REMU
  li    x30, 8; sw x30, 0(x31)
  remu  x3, x1, x2
  li    x4, 0
  bne   x3, x4, fail

  # Phase 9: DIV by zero
  li    x30, 9; sw x30, 0(x31)
  li    x1, 42
  div   x3, x1, x0
  li    x4, -1
  bne   x3, x4, fail

  # Phase 10: INT32_MIN / -1
  li    x30, 10; sw x30, 0(x31)
  lui   x1, 0x80000
  li    x2, -1
  div   x3, x1, x2
  lui   x4, 0x80000
  bne   x3, x4, fail

  li    x28, 1
  jal   x0, done

fail:
  li    x28, 0

done:
  jal   x0, done
