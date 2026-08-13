/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# eRISCV MCU DBus unmapped APB error test.
# An unimplemented APB slot must return exactly one DBus error.  A failed load
# must not write its destination register; x5 starts with a nonzero sentinel.

  .section .text
  .globl _start
  .option norvc
_start:
  lui  x1, 0x40060             # reserved v2 MMIO slot at 0x4006_0000
  li   x5, 0x11223344          # failed-load destination sentinel
  lw   x5, 0x600(x1)           # unimplemented APB slot: DBus error
  li   x6, 1                   # execution must continue after the response
  add  x24, x5, x0
  add  x25, x6, x0

done:
  jal  x0, done
