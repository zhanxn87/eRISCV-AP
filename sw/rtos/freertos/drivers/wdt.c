/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "wdt.h"

#define WDT_CTRL       0x00u
#define WDT_TIMEOUT    0x04u
#define WDT_WINDOW     0x08u
#define WDT_FEED       0x0cu
#define WDT_STATUS     0x10u
#define WDT_PRETIMEOUT 0x18u
#define WDT_FEED_MAGIC 0xACCE55EDu
#define WDT_ENABLE     (1u << 0)
#define WDT_IRQ_EN     (1u << 2)

void freertos_wdt_config(eriscv_mcu_u32 timeout, eriscv_mcu_u32 window,
                         eriscv_mcu_u32 pretimeout)
{
  eriscv_mcu_mmio_write32(ERISCV_MCU_WDT0_BASE + WDT_TIMEOUT, timeout);
  eriscv_mcu_mmio_write32(ERISCV_MCU_WDT0_BASE + WDT_WINDOW, window);
  eriscv_mcu_mmio_write32(ERISCV_MCU_WDT0_BASE + WDT_PRETIMEOUT, pretimeout);
}

void freertos_wdt_enable(int irq_enable)
{
  eriscv_mcu_u32 ctrl = WDT_ENABLE;
  if (irq_enable) {
    ctrl |= WDT_IRQ_EN;
  }
  eriscv_mcu_mmio_write32(ERISCV_MCU_WDT0_BASE + WDT_CTRL, ctrl);
}

void freertos_wdt_disable(void)
{
  eriscv_mcu_mmio_write32(ERISCV_MCU_WDT0_BASE + WDT_CTRL, 0u);
}

void freertos_wdt_feed(void)
{
  eriscv_mcu_mmio_write32(ERISCV_MCU_WDT0_BASE + WDT_FEED, WDT_FEED_MAGIC);
}

eriscv_mcu_u32 freertos_wdt_status(void)
{
  return eriscv_mcu_mmio_read32(ERISCV_MCU_WDT0_BASE + WDT_STATUS);
}
