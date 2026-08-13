/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#ifndef ERISCV_EMBENCH_STRING_H
#define ERISCV_EMBENCH_STRING_H

#include <stddef.h>

void *memcpy(void *destination, const void *source, size_t count);
void *memset(void *destination, int value, size_t count);
int memcmp(const void *left, const void *right, size_t count);
size_t strlen(const char *string);
char *strchr(const char *string, int character);
void *memmove(void *destination, const void *source, size_t count);

#endif
