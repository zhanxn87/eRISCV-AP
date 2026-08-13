/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "gpio.h"

#define GPIO_OUT 0x00u
#define GPIO_IN  0x04u
#define GPIO_DIR 0x08u

void freertos_gpio_configure_output(eriscv_mcu_u32 output_enable)
{
  eriscv_mcu_mmio_write32(ERISCV_MCU_GPIO0_BASE + GPIO_DIR, output_enable);
}

void freertos_gpio_write(eriscv_mcu_u32 value)
{
  eriscv_mcu_mmio_write32(ERISCV_MCU_GPIO0_BASE + GPIO_OUT, value);
}

eriscv_mcu_u32 freertos_gpio_read(void)
{
  return eriscv_mcu_mmio_read32(ERISCV_MCU_GPIO0_BASE + GPIO_IN);
}

void freertos_gpio_update(eriscv_mcu_u32 mask, eriscv_mcu_u32 value)
{
  eriscv_mcu_u32 output =
      eriscv_mcu_mmio_read32(ERISCV_MCU_GPIO0_BASE + GPIO_OUT);
  freertos_gpio_write((output & ~mask) | (value & mask));
}

void freertos_gpio_toggle(eriscv_mcu_u32 mask)
{
  eriscv_mcu_u32 output =
      eriscv_mcu_mmio_read32(ERISCV_MCU_GPIO0_BASE + GPIO_OUT);
  freertos_gpio_write(output ^ mask);
}
