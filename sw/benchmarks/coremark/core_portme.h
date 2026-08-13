/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#ifndef ERISCV_M2_CORE_PORTME_H
#define ERISCV_M2_CORE_PORTME_H

#define HAS_FLOAT 0
#define HAS_TIME_H 0
#define USE_CLOCK 0
#define HAS_STDIO 0
#define HAS_PRINTF 0

#define COMPILER_VERSION "riscv64-unknown-elf-gcc"
#ifndef ERISCV_COREMARK_COMPILER_FLAGS
#error "CoreMark Makefile must define ERISCV_COREMARK_COMPILER_FLAGS"
#endif
#ifndef COREMARK_CLOCK_HZ
#error "CoreMark Makefile must define COREMARK_CLOCK_HZ"
#endif
#define COMPILER_FLAGS ERISCV_COREMARK_COMPILER_FLAGS
#define MEM_LOCATION "ITCM code, DTCM static data (1:1)"

typedef signed short ee_s16;
typedef unsigned short ee_u16;
typedef signed int ee_s32;
typedef unsigned char ee_u8;
typedef unsigned int ee_u32;
typedef unsigned int ee_ptr_int;
typedef unsigned int ee_size_t;
typedef float ee_f32;

#define NULL ((void *)0)
#define align_mem(x) (void *)(4 + (((ee_ptr_int)(x) - 1) & ~3))

#define CORETIMETYPE ee_u32
typedef ee_u32 CORE_TICKS;

#define SEED_METHOD SEED_VOLATILE
#define MEM_METHOD MEM_STATIC
#define MULTITHREAD 1
#define MAIN_HAS_NOARGC 1
#define MAIN_HAS_NORETURN 0

typedef struct CORE_PORTABLE_S {
  ee_u8 portable_id;
} core_portable;

extern ee_u32 default_num_contexts;
void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);
int ee_printf(const char *fmt, ...);

#endif
