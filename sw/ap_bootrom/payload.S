/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

/* Verification payload executed only after the boot ROM copied it from BPI to
 * DDR. It proves D-Cache writeback, FENCE.I coherence, and execution transfer:
 * stage_old is fetched first, overwritten through the D-Cache, then re-entered
 * only after FENCE.I invalidates the stale I-Cache line.
 */

.option norvc
.option norelax
.section .text.init, "ax", @progbits
.align 2
.globl _start

.equ AP_DDR_MARKER_OFFSET, 0x2000
.equ AP_PAYLOAD_MARKER,    0x5041594c4f414421
.equ JALR_X0_T1,           0x00030067

_start:
  la t0, stage_old
  la t1, stage_new
  jalr ra, 0(t0)

  li t2, JALR_X0_T1
  sw t2, 0(t0)
  fence.i
  jalr zero, 0(t0)

boot_payload_fail:
  j boot_payload_fail

.align 2
stage_old:
  jalr zero, 0(ra)

stage_new:
  /* Form 0x0000_0000_8000_0000 without RV64 LUI sign extension. */
  lui t0, 0x08000
  slli t0, t0, 4
  li t1, AP_DDR_MARKER_OFFSET
  add t0, t0, t1
  li t1, AP_PAYLOAD_MARKER
  sd t1, 0(t0)
  fence.i
1:
  j 1b

/* Deliberately make the transfer span several 64-byte cache lines. */
.align 3
.fill 192, 1, 0xa5
