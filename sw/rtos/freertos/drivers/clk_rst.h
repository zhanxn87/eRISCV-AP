/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#ifndef ERISCV_FREERTOS_CLK_RST_H
#define ERISCV_FREERTOS_CLK_RST_H

#include "eriscv_mcu.h"

void freertos_clk_enable(eriscv_mcu_u32 mask);
void freertos_clk_disable(eriscv_mcu_u32 mask);
eriscv_mcu_u32 freertos_clk_status(void);
void freertos_peripheral_reset(eriscv_mcu_u32 mask);
void freertos_wfi_sleep_enable(int enable);
void freertos_enter_sleep(void);
void freertos_wake_enable(eriscv_mcu_u32 mask);
void freertos_wake_disable(eriscv_mcu_u32 mask);
eriscv_mcu_u32 freertos_wake_status(void);
void freertos_wake_status_clear(eriscv_mcu_u32 mask);
void freertos_soft_reset(void);

#endif
