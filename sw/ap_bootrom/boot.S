/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

/* First-stage AP boot ROM.
 *
 * It reads a fixed 64-byte BPI header, validates its load/entry range, copies
 * its eight-byte-aligned payload to DDR, then executes FENCE.I before jumping
 * to the payload. The boot controller only supports aligned 64-bit reads.
 */

.option norvc
.option norelax
.section .text.init, "ax", @progbits
.align 2
.globl _start

.equ AP_BPI_BASE,       0x20000000
.equ AP_BOOT_MAGIC,     0x4552495343564150
.equ AP_BOOT_VERSION,   1
.equ AP_HEADER_BYTES,   64

_start:
  lui t0, %hi(AP_BPI_BASE)

  ld t1, 0(t0)                 /* magic */
  li t2, AP_BOOT_MAGIC
  bne t1, t2, boot_fail

  ld t1, 8(t0)                 /* format version */
  li t2, AP_BOOT_VERSION
  bne t1, t2, boot_fail

  ld t3, 16(t0)                /* payload byte count */
  beqz t3, boot_fail
  andi t2, t3, 7
  bnez t2, boot_fail

  ld t4, 24(t0)                /* DDR load address */
  ld t5, 32(t0)                /* payload entry address */
  ld s0, 40(t0)                /* payload XOR checksum */

  /* AP_DDR_BASE = 0x8000_0000 without RV64 LUI sign extension. */
  lui a0, 0x08000
  slli a0, a0, 4
  bltu t4, a0, boot_fail
  li a1, 1
  slli a1, a1, 32              /* AP_DDR_LIMIT = 0x1_0000_0000 */
  add a2, t4, t3
  bltu a2, t4, boot_fail        /* unsigned overflow */
  bgtu a2, a1, boot_fail
  bltu t5, t4, boot_fail
  bgeu t5, a2, boot_fail

  addi t0, t0, AP_HEADER_BYTES
  li a4, 0
boot_copy_loop:
  ld a3, 0(t0)
  xor a4, a4, a3
  sd a3, 0(t4)
  addi t0, t0, 8
  addi t4, t4, 8
  addi t3, t3, -8
  bnez t3, boot_copy_loop

  bne a4, s0, boot_fail

  fence.i
  jalr zero, 0(t5)

boot_fail:
  wfi
  j boot_fail
