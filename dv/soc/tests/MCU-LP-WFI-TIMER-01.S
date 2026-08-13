/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# Full SoC low-power regression: TIMER0 -> PLIC -> MEIP wakes WFI sleep.

  .section .text
  .globl _start
  .option rvc
_start:
  li sp, 0x11010000

  # Install the machine external-interrupt handler.
  la x5, timer_handler
  csrw mtvec, x5

  # PLIC source 2 is TIMER0: priority=1, enabled, threshold=0.
  li x5, 0x0c000000
  li x6, 1
  sw x6, 8(x5)
  li x6, 4
  lui x7, 0x2
  add x7, x7, x5
  sw x6, 0(x7)
  lui x7, 0x200
  add x7, x7, x5
  sw x0, 0(x7)

  li x24, -1
  li x25, 0

  # Arm TIMER0 sufficiently after the WFI instruction.
  li x5, 0x40020000
  sw x0, 4(x5)
  li x6, 96
  sw x6, 8(x5)
  li x6, 3
  sw x6, 0(x5)

  # Enable automatic core clock-gating on WFI, then enable MEIP.
  li x5, 0x40050000
  li x6, 4
  sw x6, 0x10(x5)
  lw x23, 0x10(x5)
  li x6, 0x800
  csrs mie, x6
  li x6, 8
  csrs mstatus, x6

  wfi

  # Reached only after the TIMER0 interrupt handler returns with mret.
  li x25, 0x5a
  li x26, 0
done:
  j done

  .align 2
timer_handler:
  csrr x5, mcause
  li x6, 0x8000000b
  bne x5, x6, bad_cause

  # Claim TIMER0 and verify the source identity.
  li x5, 0x0c000000
  lui x6, 0x200
  addi x6, x6, 4
  add x6, x6, x5
  lw x7, 0(x6)
  li x5, 2
  bne x7, x5, bad_claim

  # Deassert the level source before PLIC completion.
  li x5, 0x40020000
  sw x0, 0(x5)
  li x8, 1
  sw x8, 0x0c(x5)
  sw x7, 0(x6)
  li x24, 1
  mret

bad_claim:
  li x24, -3
  mret
bad_cause:
  li x24, -2
  mret
