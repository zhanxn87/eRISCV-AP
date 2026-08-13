/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#ifndef ERISCV_EMBENCH_STDIO_H
#define ERISCV_EMBENCH_STDIO_H

#include <stddef.h>

typedef struct { int _dummy; } FILE;

#define stdout ((FILE *)0)
#define stderr ((FILE *)0)

int fprintf(FILE *stream, const char *format, ...);
int printf(const char *format, ...);

#endif
