/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#ifndef ERISCV_FREERTOS_PLIC_H
#define ERISCV_FREERTOS_PLIC_H

#include "eriscv_mcu.h"

void freertos_plic_init_source(eriscv_mcu_u32 source, eriscv_mcu_u32 priority);
eriscv_mcu_u32 freertos_plic_claim(void);
void freertos_plic_complete(eriscv_mcu_u32 source);

#endif
