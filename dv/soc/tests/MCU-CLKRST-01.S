/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

  .section .text
  .globl _start
  .option norvc
_start:
  # Clock/reset controller and UART bases.
  li x1, 0x40050000
  li x10, 0x40000000

  # POR cause and boot-safe effective clock state.
  lw x2, 0x0c(x1)
  lw x3, 0x04(x1)

  # Give UART observable non-reset state before gating it.
  li x18, 12
  sw x18, 0x0c(x10)
  lw x19, 0x0c(x10)

  # Disable UART clock. The stopped-domain APB policy must complete with zero.
  li x4, 0x1e
  sw x4, 0x00(x1)
  lw x5, 0x04(x1)
  lw x6, 0x0c(x10)

  # Reset UART while gated. Reset/release overrides must temporarily enable it.
  li x7, 1
  sw x7, 0x08(x1)
  lw x8, 0x04(x1)

  # Wait until the 16-cycle reset and 2-cycle clock-release extension finish.
  li x9, 64
  li x12, 0
wait_reset_release:
  lw x8, 0x04(x1)
  andi x11, x8, 1
  beq x11, x0, reset_released
  addi x9, x9, -1
  bne x9, x0, wait_reset_release
  li x12, 1
  j done

reset_released:
  # Re-enable all domains and prove that UART returned to its reset value.
  li x4, 0x1f
  sw x4, 0x00(x1)
  lw x13, 0x04(x1)
  lw x14, 0x0c(x10)

  # Verify wake-mask storage and byte-strobe semantics on CLK_EN.
  li x15, 0x7ff
  sw x15, 0x14(x1)
  lw x16, 0x14(x1)
  sb x0, 0x00(x1)
  lw x17, 0x04(x1)
  sw x4, 0x00(x1)

done:
  j done
