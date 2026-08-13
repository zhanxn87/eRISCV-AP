/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#ifndef ERISCV_FREERTOS_WDT_H
#define ERISCV_FREERTOS_WDT_H

#include "eriscv_mcu.h"

void freertos_wdt_config(eriscv_mcu_u32 timeout, eriscv_mcu_u32 window,
                         eriscv_mcu_u32 pretimeout);
void freertos_wdt_enable(int irq_enable);
void freertos_wdt_disable(void);
void freertos_wdt_feed(void);
eriscv_mcu_u32 freertos_wdt_status(void);

#endif
