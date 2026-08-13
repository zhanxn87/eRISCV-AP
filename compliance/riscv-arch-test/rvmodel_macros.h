/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#ifndef _ERISCV_RVMODEL_MACROS_H
#define _ERISCV_RVMODEL_MACROS_H

/*
 * Current ACT4 bring-up uses Sail as the reference model, so this target file
 * keeps the educational CPU boot/trap contract while mirroring Sail's helper
 * interfaces for console output, timer wiring, and synthetic interrupt control.
 */

#define RVMODEL_DATA_SECTION \
        .pushsection .tohost,"aw",@progbits;                \
        .balign 8; .global tohost; tohost: .dword 0;         \
        .balign 8; .global fromhost; fromhost: .dword 0;     \
        .popsection
#define STANDARD_SM_SUPPORTED

/*
 * The ACT trap handler skeleton currently expands to an 18-cause trampoline for
 * this RV32 machine-mode-only target. Leaving the default 24-cause count shifts
 * the saved common-entry pointer by 0x18 and drops execution into the middle of
 * common_Mentry after an ECALL.
 */
#define NUM_SPECD_INTCAUSES 18
#define INT_CAUSE_MSK ((1 << 5) - 1)
#define NUM_SPECD_EXCPTCAUSES 24
#define EXCPT_CAUSE_MSK ((1 << 5) - 1)

/* Local CPU bring-up currently assumes M-mode entry is available. */
/* #define RVMODEL_BOOT */

/*
 * The default ACT4 RVTEST_BOOT_TO_MMODE path unconditionally touches HPM CSRs
 * such as mhpmevent3..31. The educational CPU does not implement that bank,
 * so keep a minimal M-mode bring-up that installs the machine trap handler and
 * initializes only the CSRs the DUT actually exposes today.
 */
#ifdef U_SUPPORTED
#define RVMODEL_PMP_ALLOW_LOWER_MODE  li t0, -1          ;   csrw pmpaddr0, t0       ;   li t0, 0x0f             ;   csrw pmpcfg0, t0
#else
#define RVMODEL_PMP_ALLOW_LOWER_MODE
#endif

#define RVMODEL_BOOT_TO_MMODE   csrw mie, zero          ;   csrw mip, zero          ;   csrw mepc, zero         ;   csrw mtval, zero        ;   csrw mcause, zero       ;   RVMODEL_PMP_ALLOW_LOWER_MODE ;   RVTEST_TRAP_PROLOG M    ;   csrr t1, mscratch       ;   sw zero, 0(t1)          ;   la t0, common_Mentry    ;   sw t0, tentry_addr_off(t1) ;   li t0, MSTATUS_MPP      ;   csrw mstatus, t0

/*
 * ACT4's fixed-length LA helper defaults to 32-byte alignment, which leaves
 * illegal padding between rvtest_entry_point and the following jalr on this
 * RV32I-only DUT. Keep it at 4-byte alignment so boot falls through cleanly.
 */
#ifdef UNROLLSZ
#undef UNROLLSZ
#endif
#define UNROLLSZ 2

#define RVMODEL_HALT_PASS   la t0, tohost         ;   li gp, 1              ;   sw gp, 0(t0)          ; 1:                      ;   j 1b

#define RVMODEL_HALT_FAIL   la t0, tohost         ;   li gp, 3              ;   sw gp, 0(t0)          ; 1:                      ;   j 1b

#define RVMODEL_IO_WRITE_STR(_R1, _R2, _R3, _STR_PTR) 1:                           ;   lbu _R1, 0(_STR_PTR)       ;   beqz _R1, 3f               ; 2:                           ;   la _R2, tohost             ;   sw _R1, 0(_R2)             ;   li _R1, 0x01010000         ;   sw _R1, 4(_R2)             ;   addi _STR_PTR, _STR_PTR, 1 ;   j 1b                       ; 3:

#define SAIL_CLINT_BASE_ADDRESS 0x02000000
#define SAIL_SIG_ADDRESS (0x0C000000 + 0x4)
#define SAIL_MSIP_ADDRESS (SAIL_CLINT_BASE_ADDRESS + 0x0)

#define RVMODEL_MTIMECMP_ADDRESS 0x02004000
#define RVMODEL_MTIME_ADDRESS 0x0200BFF8

#define RVMODEL_INTERRUPT_LATENCY 1
#define RVMODEL_TIMER_INT_SOON_DELAY 100

#define RVMODEL_SET_MEXT_INT(_R1, _R2)   li _R1, (1 << 31) | (1 << 11);   li _R2, SAIL_SIG_ADDRESS;        sw _R1, 0(_R2)

#define RVMODEL_CLR_MEXT_INT(_R1, _R2)   li _R1, (1 << 11);                li _R2, SAIL_SIG_ADDRESS;         sw _R1, 0(_R2)

#define RVMODEL_SET_MSW_INT(_R1, _R2)   li _R1, 1;                      li _R2, SAIL_MSIP_ADDRESS;      sw _R1, 0(_R2)

#define RVMODEL_CLR_MSW_INT(_R1, _R2)   li _R2, SAIL_MSIP_ADDRESS;      sw zero, 0(_R2)

#define RVMODEL_SET_SEXT_INT(_R1, _R2)   li _R1, (1 << 31) | (1 << 9);   li _R2, SAIL_SIG_ADDRESS;       sw _R1, 0(_R2)

#define RVMODEL_CLR_SEXT_INT(_R1, _R2)   li _R1, (1 << 9);                li _R2, SAIL_SIG_ADDRESS;        sw _R1, 0(_R2)

#define RVMODEL_SET_SSW_INT(_R1, _R2)   li _R1, (1 << 31) | (1 << 1);   li _R2, SAIL_SIG_ADDRESS;       sw _R1, 0(_R2)

#define RVMODEL_CLR_SSW_INT(_R1, _R2)   li _R1, (1 << 1);                li _R2, SAIL_SIG_ADDRESS;        sw _R1, 0(_R2)

#endif
