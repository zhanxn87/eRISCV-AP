/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#ifndef ERISCV_FREERTOS_GPIO_H
#define ERISCV_FREERTOS_GPIO_H

#include "eriscv_mcu.h"

void freertos_gpio_configure_output(eriscv_mcu_u32 output_enable);
void freertos_gpio_write(eriscv_mcu_u32 value);
eriscv_mcu_u32 freertos_gpio_read(void);
void freertos_gpio_update(eriscv_mcu_u32 mask, eriscv_mcu_u32 value);
void freertos_gpio_toggle(eriscv_mcu_u32 mask);

#endif
