/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "timer.h"

#define TIMER_CTRL    0x00u
#define TIMER_COUNT   0x04u
#define TIMER_COMPARE 0x08u
#define TIMER_STATUS  0x0cu
#define TIMER_ENABLE  (1u << 0)
#define TIMER_IRQ_EN  (1u << 1)

void freertos_timer_start(eriscv_mcu_u32 compare, int irq_enable)
{
  eriscv_mcu_u32 ctrl = TIMER_ENABLE;
  if (irq_enable) {
    ctrl |= TIMER_IRQ_EN;
  }
  eriscv_mcu_mmio_write32(ERISCV_MCU_TIMER0_BASE + TIMER_COMPARE, compare);
  eriscv_mcu_mmio_write32(ERISCV_MCU_TIMER0_BASE + TIMER_COUNT, 0u);
  eriscv_mcu_mmio_write32(ERISCV_MCU_TIMER0_BASE + TIMER_CTRL, ctrl);
}

void freertos_timer_stop(void)
{
  eriscv_mcu_mmio_write32(ERISCV_MCU_TIMER0_BASE + TIMER_CTRL, 0u);
  eriscv_mcu_mmio_write32(ERISCV_MCU_TIMER0_BASE + TIMER_STATUS, 1u);
}

int freertos_timer_expired(void)
{
  return (eriscv_mcu_mmio_read32(ERISCV_MCU_TIMER0_BASE + TIMER_STATUS) & 1u) != 0u;
}

eriscv_mcu_u32 freertos_timer_count(void)
{
  return eriscv_mcu_mmio_read32(ERISCV_MCU_TIMER0_BASE + TIMER_COUNT);
}
