/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# eRISCV MCU PLIC interrupt-driven test.
# Tests: source pending → MEIP → trap → claim → complete.

  .section .text
  .globl _start
  .option rvc
_start:
  li sp, 0x11010000

  # Setup mtvec to trap handler
  la x5, plic_handler
  csrw mtvec, x5

  # Setup PLIC: priority[17]=5, threshold=0, enable external source 17.
  li x5, 0x0C000000           # PLIC_BASE
  li x6, 5
  sw x6, 68(x5)                # priority[17] = 5; source 0 is reserved

  li x6, 0x00020000            # enable word bit 17 corresponds to source ID 17
  lui x7, 2
  add x7, x5, x7               # PLIC_BASE + 0x2000 (enable)
  sw x6, 0(x7)                 # enable[1] = 1

  # Initialize result state before an interrupt can be taken.
  li x24, -1                   # -1 = not yet interrupted

  # Enable MEIP in MIE, then global interrupts in mstatus.
  li x6, 0x800                 # MEIP bit (11)
  csrs mie, x6
  li x6, 0x8                   # MIE bit (3)
  csrs mstatus, x6

  # Wait for interrupt (spin)
  li x25, 0
wait_loop:
  addi x25, x25, 1
  bnez x24, wait_loop          # x24 changes to 0 when handler runs

  # Success: x24 = 0
pass:
  j .

fail:
  li x24, -2
  j .

# ============================================================
# PLIC trap handler (M-mode, external interrupt)
# ============================================================
  .align 2
plic_handler:
  # Save registers
  addi sp, sp, -16
  sw x5, 0(sp)
  sw x6, 4(sp)
  sw x7, 8(sp)

  # Check mcause for MEIP
  csrr x5, mcause
  li x6, 0x8000000b            # mcause[31]=1 for interrupt, code=11 for MEIP
  bne x5, x6, not_meip

  # Claim PLIC
  li x5, 0x0C000000
  lui x6, 0x200
  addi x6, x6, 4               # 0x200004
  add x6, x5, x6
  lw x7, 0(x6)                 # claim — returns source ID (should be 17)

  # Verify claimed source = 17
  li x5, 17
  bne x7, x5, claim_err

  # Complete: write source ID back
  sw x7, 0(x6)

  # Mark test as passed
  li x24, 0

  j handler_done

claim_err:
  li x24, -3

not_meip:
handler_done:
  lw x5, 0(sp)
  lw x6, 4(sp)
  lw x7, 8(sp)
  addi sp, sp, 16
  mret
