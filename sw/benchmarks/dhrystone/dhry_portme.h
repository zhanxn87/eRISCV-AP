/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

/*
 * dhry_portme.h — eRISCV-M2 Dhrystone port configuration.
 */
#ifndef ERISCV_DHRY_PORTME_H
#define ERISCV_DHRY_PORTME_H

/* Compiler options and clock rate are supplied by the Makefile/runner. */
#define DHRY_COMPILER_VERSION "riscv64-unknown-elf-gcc"

/* Type map for Dhrystone */
typedef signed short   dhry_s16;
typedef unsigned short dhry_u16;
typedef signed int     dhry_s32;
typedef unsigned char  dhry_u8;
typedef unsigned int   dhry_u32;
typedef unsigned int   dhry_ptr_int;
typedef unsigned int   dhry_size_t;

/* Result encoding */
#define DHRY_RESULT_PASS_MASK  0x80000000u
#define DHRY_RESULT_FAIL_MASK  0x40000000u
#define DHRY_RESULT_CYCLE_MASK 0x3fffffffu

#endif
