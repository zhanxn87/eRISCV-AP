/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#ifndef FREERTOS_UMODE_PMP_CONTEXT_H
#define FREERTOS_UMODE_PMP_CONTEXT_H

#include "FreeRTOS.h"
#include "task.h"

void eriscv_umode_pmp_register(TaskHandle_t task, eriscv_mcu_u32 user_dmem_base);
void eriscv_umode_pmp_load(TaskHandle_t task);
void eriscv_umode_pmp_load_current(void);
void __wrap_vTaskSwitchContext(void);

#endif
