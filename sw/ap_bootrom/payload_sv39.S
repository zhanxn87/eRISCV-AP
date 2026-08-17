/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

/* Boot-chain Sv39 integration payload.
 *
 * M-mode builds a root/L1/L0 page table in DDR, drains it through FENCE.I,
 * enters S-mode at a virtual address mapped to this payload, then performs a
 * load/store through a second mapped page.  A/D begin clear so the test also
 * exercises the PTW atomic update path.
 */

.option norvc
.option norelax
.section .text.init, "ax", @progbits
.align 2
.globl _start

.equ AP_ROOT_PTE_ADDR,       0x0000000080001008
.equ AP_L1_PTE_ADDR,         0x0000000080002000
.equ AP_L0_CODE_PTE_ADDR,    0x0000000080003000
.equ AP_L0_DATA_PTE_ADDR,    0x0000000080003008
.equ AP_ROOT_TO_L1_PTE,      0x0000000020000801
.equ AP_L1_TO_L0_PTE,        0x0000000020000c01
.equ AP_CODE_LEAF_PTE,       0x000000002000400f
.equ AP_DATA_LEAF_PTE,       0x000000002000440f
.equ AP_SATP_SV39_ROOT,      0x8000000000080001
.equ AP_SMODE_ENTRY_VA,      0x0000000040000100
.equ AP_SMODE_DATA_VA,       0x0000000040001000
.equ AP_SMODE_MARKER,        0x53563339504f5354

_start:
  li t0, AP_ROOT_PTE_ADDR
  li t1, AP_ROOT_TO_L1_PTE
  sd t1, 0(t0)

  li t0, AP_L1_PTE_ADDR
  li t1, AP_L1_TO_L0_PTE
  sd t1, 0(t0)

  li t0, AP_L0_CODE_PTE_ADDR
  li t1, AP_CODE_LEAF_PTE
  sd t1, 0(t0)

  li t0, AP_L0_DATA_PTE_ADDR
  li t1, AP_DATA_LEAF_PTE
  sd t1, 0(t0)

  /* PTE writes must reach DDR before a translated fetch can walk them. */
  fence.i
  sfence.vma x0, x0
  li t0, AP_SATP_SV39_ROOT
  csrw satp, t0
  sfence.vma x0, x0

  /* mstatus.MPP = S, then return to the mapped payload page. */
  li t0, 0x1800
  csrc mstatus, t0
  li t0, 0x0800
  csrs mstatus, t0
  li t0, AP_SMODE_ENTRY_VA
  csrw mepc, t0
  mret

.balign 256
s_mode_entry:
  li t0, AP_SMODE_DATA_VA
  ld t1, 0(t0)
  li t2, AP_SMODE_MARKER
  sd t2, 0(t0)
  fence.i
1:
  j 1b
