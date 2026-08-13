/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#ifndef ERISCV_FREERTOS_STRING_H
#define ERISCV_FREERTOS_STRING_H

#include "stdlib.h"

void *memcpy(void *destination, const void *source, size_t count);
void *memset(void *destination, int value, size_t count);

#endif
