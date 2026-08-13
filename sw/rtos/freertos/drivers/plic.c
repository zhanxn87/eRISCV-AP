/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "plic.h"

void freertos_plic_init_source(eriscv_mcu_u32 source, eriscv_mcu_u32 priority)
{
  eriscv_mcu_u32 address;
  eriscv_mcu_u32 value;

  if (source == 0u || source > ERISCV_MCU_PLIC_SOURCES) {
    return;
  }
  eriscv_mcu_mmio_write32(ERISCV_MCU_PLIC_BASE +
                              ERISCV_MCU_PLIC_PRIORITY(source),
                          priority & 7u);
  address = ERISCV_MCU_PLIC_BASE + ERISCV_MCU_PLIC_ENABLE +
            4u * (source >> 5);
  value = eriscv_mcu_mmio_read32(address);
  value |= 1u << (source & 31u);
  eriscv_mcu_mmio_write32(address, value);
  eriscv_mcu_mmio_write32(ERISCV_MCU_PLIC_BASE + ERISCV_MCU_PLIC_THRESHOLD, 0u);
}

eriscv_mcu_u32 freertos_plic_claim(void)
{
  return eriscv_mcu_mmio_read32(ERISCV_MCU_PLIC_BASE + ERISCV_MCU_PLIC_CLAIM);
}

void freertos_plic_complete(eriscv_mcu_u32 source)
{
  eriscv_mcu_mmio_write32(ERISCV_MCU_PLIC_BASE + ERISCV_MCU_PLIC_CLAIM, source);
}
