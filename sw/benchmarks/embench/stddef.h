/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#ifndef ERISCV_EMBENCH_STDDEF_H
#define ERISCV_EMBENCH_STDDEF_H

typedef unsigned int size_t;
#define NULL ((void *)0)
#define offsetof(type, member) __builtin_offsetof(type, member)

#endif
