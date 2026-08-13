/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "eriscv_mcu.h"

#define DMA_WORDS       4u

static volatile eriscv_mcu_u32 source[DMA_WORDS] ERISCV_MCU_SYSTEM_SRAM_BUFFER;
static volatile eriscv_mcu_u32 destination[DMA_WORDS] ERISCV_MCU_SYSTEM_SRAM_BUFFER;

int main(void)
{
  eriscv_mcu_u32 index;
  int result;

	eriscv_mcu_uart_init(ERISCV_MCU_UART_DIVISOR);
  eriscv_mcu_gpio_set_direction(1u);
  for (index = 0u; index < DMA_WORDS; ++index) {
    source[index] = 0x24680000u + index;
    destination[index] = 0u;
  }

  result = eriscv_mcu_dma_start((eriscv_mcu_u32)(unsigned long)source,
                                (eriscv_mcu_u32)(unsigned long)destination,
                                DMA_WORDS * sizeof(source[0]), 0);
  if (result == ERISCV_MCU_DMA_OK) {
    result = eriscv_mcu_dma_wait(10000u);
  }
  for (index = 0u; result == ERISCV_MCU_DMA_OK && index < DMA_WORDS; ++index) {
    if (destination[index] != source[index]) {
      result = ERISCV_MCU_DMA_EIO;
    }
  }
  eriscv_mcu_dma_clear_status();
  eriscv_mcu_gpio_write(result == ERISCV_MCU_DMA_OK ? 1u : (eriscv_mcu_u32)(-result));
  eriscv_mcu_uart_puts(result == ERISCV_MCU_DMA_OK ?
                      "eRISCV-M2 DMA PASS\n" : "eRISCV-M2 DMA FAIL\n");
  for (;;) {
  }
}
