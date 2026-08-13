/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# MCU-HPM-01: Specification-driven HPM ABI verification.
#
# Verifies the HPM v1.0 contract for four 64-bit programmable counters.
# Self-checking: x28 = 1 at done means PASS; any check failure jumps to fail
# with x28 = 0.
#
# Uses only RTL-supported events (as of M2 CSR HPM-event sanitizer):
#   NONE(0x00), BRANCH_TAKEN(0x04), EXCEPTION_TAKEN(0x06),
#   INTERRUPT_TAKEN(0x07), IFETCH_WAIT_CYCLES(0x08),
#   DATA_WAIT_CYCLES(0x09), PIPELINE_STALL_CYCLES(0x0A),
#   LOAD_USE_STALL_CYCLES(0x0B), WFI_CYCLES(0x0E),
#   DEBUG_ENTRY(0x12), IRQ_PENDING_CYCLES(0x13)
#
# Coverage:
#   - Reset defaults: HPM3=0x08, HPM4=0x09, HPM5=0x04, HPM6=0x07
#   - CSR r/w: low/high-half, mhpmevent, mcountinhibit
#   - Unsupported-event WARL → EVENT_NONE
#   - mcounteren delegated-counter gates are covered by MCU-HPM-CSR-01
#   - Machine + URO aliases accessible
#   - Deterministic BRANCH_TAKEN counting
#   - Event-selection isolation (BRANCH_TAKEN vs EVENT_NONE)
#   - Per-counter inhibit isolation
#   - 64-bit carry on overflow

  .globl _start
_start:

  # =========================================================================
  # P2.1 — Reset default selectors
  # =========================================================================
  csrr  x10, mhpmevent3       # expect 0x08 (IFETCH_WAIT_CYCLES)
  csrr  x11, mhpmevent4       # expect 0x09 (DATA_WAIT_CYCLES)
  csrr  x12, mhpmevent5       # expect 0x04 (BRANCH_TAKEN)
  csrr  x13, mhpmevent6       # expect 0x07 (INTERRUPT_TAKEN)
  li    x1, 0x08
  bne   x10, x1,  fail
  li    x1, 0x09
  bne   x11, x1,  fail
  li    x1, 0x04
  bne   x12, x1,  fail
  li    x1, 0x07
  bne   x13, x1,  fail

  # =========================================================================
  # P2.2 — Low-half counter CSR r/w
  # =========================================================================
  li    x1, 0xDEADBEEF
  csrw  mhpmcounter3, x1
  csrr  x14, mhpmcounter3
  bne   x14, x1,  fail
  li    x1, 0xCAFEBABE
  csrw  mhpmcounter4, x1
  csrr  x15, mhpmcounter4
  bne   x15, x1,  fail
  li    x1, 0x12345678
  csrw  mhpmcounter5, x1
  csrr  x3, mhpmcounter5
  bne   x3, x1,  fail
  li    x1, 0x9ABCDEF0
  csrw  mhpmcounter6, x1
  csrr  x4, mhpmcounter6
  bne   x4, x1,  fail

  # =========================================================================
  # P2.3 — High-half counter CSR r/w
  # =========================================================================
  li    x1, 0xAABBCCDD
  csrw  mhpmcounter3h, x1
  csrr  x5, mhpmcounter3h
  bne   x5, x1,  fail
  li    x1, 0x11223344
  csrw  mhpmcounter4h, x1
  csrr  x6, mhpmcounter4h
  bne   x6, x1,  fail
  li    x1, 0x55667788
  csrw  mhpmcounter5h, x1
  csrr  x7, mhpmcounter5h
  bne   x7, x1,  fail
  li    x1, 0x99AABBCC
  csrw  mhpmcounter6h, x1
  csrr  x8, mhpmcounter6h
  bne   x8, x1,  fail

  # =========================================================================
  # P2.4 — Event selector r/w (supported events only)
  # =========================================================================
  li    x1, 0x04                # BRANCH_TAKEN
  csrw  mhpmevent3, x1
  csrr  x9, mhpmevent3
  bne   x9, x1,  fail
  li    x1, 0x07                # INTERRUPT_TAKEN
  csrw  mhpmevent4, x1
  csrr  x10, mhpmevent4
  bne   x10, x1,  fail
  li    x1, 0x08                # IFETCH_WAIT_CYCLES
  csrw  mhpmevent5, x1
  csrr  x11, mhpmevent5
  bne   x11, x1,  fail
  li    x1, 0x00                # EVENT_NONE
  csrw  mhpmevent6, x1
  csrr  x12, mhpmevent6
  bne   x12, x1,  fail

  # =========================================================================
  # P2.5 — Unsupported-event WARL → EVENT_NONE
  # =========================================================================
  li    x1, 0xFF
  csrw  mhpmevent3, x1
  csrr  x13, mhpmevent3        # expect 0x00
  bne   x13, x0,  fail
  li    x1, 0x80
  csrw  mhpmevent4, x1
  csrr  x14, mhpmevent4        # expect 0x00
  bne   x14, x0,  fail
  li    x1, 0x40
  csrw  mhpmevent5, x1
  csrr  x15, mhpmevent5        # expect 0x00
  bne   x15, x0,  fail

  # =========================================================================
  # P2.6 — mcountinhibit mask + freeze
  # mcounteren delegation is verified separately by MCU-HPM-CSR-01 and
  # MCU-UMODE-EXT-01.
  # =========================================================================
  li    x1, 0x7D                # CY(0) + IR(2) + HPM3-6(3-6)
  csrw  mcountinhibit, x1
  csrr  x17, mcountinhibit      # expect 0x7D
  li    x1, 0x7D
  bne   x17, x1,  fail

  # Verify HPM5 frozen when inhibited
  csrr  x3, mhpmcounter5
  nop
  nop
  csrr  x4, mhpmcounter5
  bne   x3, x4,  fail
  csrw  mcountinhibit, x0

  # =========================================================================
  # P2.8 — Machine aliases accessible
  # =========================================================================
  csrr  x18, mcycle
  csrr  x19, minstret
  csrr  x20, mhpmcounter3
  csrr  x21, mhpmcounter4
  csrr  x22, mhpmcounter5
  csrr  x23, mhpmcounter6

  # =========================================================================
  # P2.9 — Unprivileged aliases accessible
  # =========================================================================
  csrr  x24, cycle
  csrr  x25, instret
  csrr  x26, hpmcounter3
  csrr  x27, hpmcounter4
  csrr  x29, hpmcounter5
  csrr  x30, hpmcounter6

  # =========================================================================
  # P2.10 — Deterministic BRANCH_TAKEN event
  # =========================================================================
  csrw  mhpmcounter3, x0
  li    x1, 0x04
  csrw  mhpmevent3, x1
  beq   x0, x0, 1f
  addi  x0, x0, 0
1:
  csrr  x3, mhpmcounter3        # expect >= 1
  beq   x3, x0,  fail

  # =========================================================================
  # P2.11 — Event-selection isolation
  # =========================================================================
  csrw  mhpmcounter3, x0
  csrw  mhpmcounter4, x0
  csrw  mhpmcounter5, x0
  csrw  mhpmcounter6, x0

  li    x1, 0x04                # HPM3=BRANCH_TAKEN
  csrw  mhpmevent3, x1
  csrw  mhpmevent4, x0          # HPM4=NONE
  csrw  mhpmevent5, x0          # HPM5=NONE
  csrw  mhpmevent6, x0          # HPM6=NONE

  beq   x0, x0, 2f
  addi  x0, x0, 0
2:

  csrr  x3, mhpmcounter3        # expect >= 1
  beq   x3, x0,  fail
  csrr  x4, mhpmcounter4        # expect 0
  bne   x4, x0,  fail
  csrr  x5, mhpmcounter5        # expect 0
  bne   x5, x0,  fail
  csrr  x6, mhpmcounter6        # expect 0
  bne   x6, x0,  fail

  # =========================================================================
  # P2.12 — Per-counter inhibit isolation
  # =========================================================================
  csrw  mhpmcounter3, x0
  csrw  mhpmcounter4, x0
  csrw  mhpmcounter5, x0
  csrw  mhpmcounter6, x0
  li    x1, 0x04
  csrw  mhpmevent3, x1
  csrw  mhpmevent4, x1
  csrw  mhpmevent5, x1
  csrw  mhpmevent6, x1

  li    x1, 0x30                # inhibit HPM4(bit4) + HPM5(bit5)
  csrw  mcountinhibit, x1

  beq   x0, x0, 3f
  addi  x0, x0, 0
3:

  csrr  x7, mhpmcounter3        # expect >= 1 (not inhibited)
  beq   x7, x0,  fail
  csrr  x8, mhpmcounter4        # expect 0 (inhibited)
  bne   x8, x0,  fail
  csrr  x9, mhpmcounter5        # expect 0 (inhibited)
  bne   x9, x0,  fail
  csrr  x10, mhpmcounter6       # expect >= 1 (not inhibited)
  beq   x10, x0,  fail
  csrw  mcountinhibit, x0

  # =========================================================================
  # P2.13 — 64-bit carry on overflow
  # =========================================================================
  li    x1, -1                  # 0xFFFFFFFF
  csrw  mhpmcounter3, x1
  csrw  mhpmcounter3h, x0
  li    x1, 0x04
  csrw  mhpmevent3, x1

  beq   x0, x0, 4f
  addi  x0, x0, 0
4:

  csrr  x11, mhpmcounter3       # expect 0 (wrapped)
  bne   x11, x0,  fail
  csrr  x12, mhpmcounter3h      # expect 1 (carry)
  li    x1, 1
  bne   x12, x1,  fail

  # =========================================================================
  # PASS
  # =========================================================================
  li    x28, 1
  jal   x0, done

fail:
  li    x28, 0

done:
  jal   x0, done
