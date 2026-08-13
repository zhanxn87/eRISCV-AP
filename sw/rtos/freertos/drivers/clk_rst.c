/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "clk_rst.h"

#define CLK_EN       0x00u
#define CLK_STATUS   0x04u
#define PERI_RESET   0x08u
#define SLEEP_CTRL   0x10u
#define WAKE_ENABLE  0x14u
#define WAKE_STATUS  0x18u
#define SOFT_RESET   0x1cu
#define CLK_MASK     0x1fu
#define WAKE_MASK    0x7ffu
#define SLEEP_REQ    (1u << 0)
#define WFI_SLEEP_EN (1u << 2)

void freertos_clk_enable(eriscv_mcu_u32 mask)
{
  eriscv_mcu_u32 value =
      eriscv_mcu_mmio_read32(ERISCV_MCU_CLK_RST_BASE + CLK_EN);
  eriscv_mcu_mmio_write32(ERISCV_MCU_CLK_RST_BASE + CLK_EN,
                           value | (mask & CLK_MASK));
}

void freertos_clk_disable(eriscv_mcu_u32 mask)
{
  eriscv_mcu_u32 value =
      eriscv_mcu_mmio_read32(ERISCV_MCU_CLK_RST_BASE + CLK_EN);
  eriscv_mcu_mmio_write32(ERISCV_MCU_CLK_RST_BASE + CLK_EN,
                           value & ~(mask & CLK_MASK));
}

eriscv_mcu_u32 freertos_clk_status(void)
{
  return eriscv_mcu_mmio_read32(ERISCV_MCU_CLK_RST_BASE + CLK_STATUS);
}

void freertos_peripheral_reset(eriscv_mcu_u32 mask)
{
  eriscv_mcu_mmio_write32(ERISCV_MCU_CLK_RST_BASE + PERI_RESET,
                           mask & CLK_MASK);
}

void freertos_wfi_sleep_enable(int enable)
{
  eriscv_mcu_mmio_write32(ERISCV_MCU_CLK_RST_BASE + SLEEP_CTRL,
                           enable ? WFI_SLEEP_EN : 0u);
}

void freertos_enter_sleep(void)
{
  eriscv_mcu_mmio_write32(ERISCV_MCU_CLK_RST_BASE + SLEEP_CTRL, SLEEP_REQ);
  __asm__ volatile ("fence iorw, iorw" ::: "memory");
  __asm__ volatile ("wfi");
}

void freertos_wake_enable(eriscv_mcu_u32 mask)
{
  eriscv_mcu_u32 value =
      eriscv_mcu_mmio_read32(ERISCV_MCU_CLK_RST_BASE + WAKE_ENABLE);
  eriscv_mcu_mmio_write32(ERISCV_MCU_CLK_RST_BASE + WAKE_ENABLE,
                           value | (mask & WAKE_MASK));
}

void freertos_wake_disable(eriscv_mcu_u32 mask)
{
  eriscv_mcu_u32 value =
      eriscv_mcu_mmio_read32(ERISCV_MCU_CLK_RST_BASE + WAKE_ENABLE);
  eriscv_mcu_mmio_write32(ERISCV_MCU_CLK_RST_BASE + WAKE_ENABLE,
                           value & ~(mask & WAKE_MASK));
}

eriscv_mcu_u32 freertos_wake_status(void)
{
  return eriscv_mcu_mmio_read32(ERISCV_MCU_CLK_RST_BASE + WAKE_STATUS);
}

void freertos_wake_status_clear(eriscv_mcu_u32 mask)
{
  eriscv_mcu_mmio_write32(ERISCV_MCU_CLK_RST_BASE + WAKE_STATUS,
                           mask & WAKE_MASK);
}

void freertos_soft_reset(void)
{
  eriscv_mcu_mmio_write32(ERISCV_MCU_CLK_RST_BASE + SOFT_RESET, 1u);
}
