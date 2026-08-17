/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# eRISCV MCU RV32C load/store directed test.
# Covers compressed register-form and stack-form load/store offsets.

  .section .text
  .globl _start
  .option rvc
_start:
  li sp, 0x11010000
  addi sp, sp, -256
  mv x8, sp              # x8/s0 is a compressed-register base

  li x24, 0
  li x25, 0
  li x26, 0
  li x27, 0
  li x28, 0
  li x29, 0
  li x30, 0
  li x31, 0

  # Register-form c.sw/c.lw at low and high encoded offsets.
  li x9, 0x11223344
  c.sw x9, 0(x8)
  c.lw x10, 0(x8)
  sub x24, x10, x9

  li x9, 0x55667788
  c.sw x9, 4(x8)
  c.lw x10, 4(x8)
  sub x25, x10, x9

  li x9, 0x13579bdf
  c.sw x9, 124(x8)
  c.lw x10, 124(x8)
  sub x26, x10, x9

  # Stack-form c.swsp/c.lwsp at low and higher offsets.
  li x11, 0x2468ace0
  c.swsp x11, 0(sp)
  c.lwsp x12, 0(sp)
  sub x27, x12, x11

  li x11, 0x0badcafe
  c.swsp x11, 252(sp)
  c.lwsp x12, 252(sp)
  sub x28, x12, x11

  # Cross-check register-form store with regular lw and regular sw with c.lw.
  li x9, 0xa5a55a5a
  c.sw x9, 8(x8)
  lw x10, 8(x8)
  sub x29, x10, x9

  li x9, 0xdeadbeef
  sw x9, 12(x8)
  c.lw x10, 12(x8)
  sub x30, x10, x9

  add x31, x24, x25
  add x31, x31, x26
  add x31, x31, x27
  add x31, x31, x28
  add x31, x31, x29
  add x31, x31, x30

  # c.lw -> c.slli is a compressed load-use dependency.
  li x9, 0x15
  c.sw x9, 16(x8)
  c.lw x10, 16(x8)
  c.slli x10, 1
  li x11, 0x2a
  sub x10, x10, x11
  add x31, x31, x10
pass:
  j pass
