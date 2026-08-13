/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#ifndef ERISCV_EMBENCH_ASSERT_H
#define ERISCV_EMBENCH_ASSERT_H

#include <stdlib.h>

#define assert(expression) ((expression) ? (void)0 : abort())

#endif
