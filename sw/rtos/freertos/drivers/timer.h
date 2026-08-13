/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#ifndef ERISCV_FREERTOS_TIMER_H
#define ERISCV_FREERTOS_TIMER_H

#include "eriscv_mcu.h"

void freertos_timer_start(eriscv_mcu_u32 compare, int irq_enable);
void freertos_timer_stop(void);
int freertos_timer_expired(void);
eriscv_mcu_u32 freertos_timer_count(void);

#endif
