/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "eriscv_mcu.h"

#define DMA_WORDS 4u

static volatile eriscv_mcu_u32 source[DMA_WORDS] ERISCV_MCU_SYSTEM_SRAM_BUFFER;
static volatile eriscv_mcu_u32 destination[DMA_WORDS] ERISCV_MCU_SYSTEM_SRAM_BUFFER;
static volatile eriscv_mcu_u32 dma_completion_status;

void eriscv_mcu_dma_complete_handler(eriscv_mcu_u32 status)
{
  dma_completion_status = status;
}

int main(void)
{
  eriscv_mcu_u32 index;
  int result;

	eriscv_mcu_uart_init(ERISCV_MCU_UART_DIVISOR);
  eriscv_mcu_gpio_set_direction(1u);
  for (index = 0u; index < DMA_WORDS; ++index) {
    source[index] = 0x5a5a0000u + index;
    destination[index] = 0u;
  }

  eriscv_mcu_dma_irq_enable(1u);
  eriscv_mcu_enable_machine_irqs(ERISCV_MCU_MIE_MEIE);
  result = eriscv_mcu_dma_start((eriscv_mcu_u32)(unsigned long)source,
                                (eriscv_mcu_u32)(unsigned long)destination,
                                DMA_WORDS * sizeof(source[0]), 1);
  while (result == ERISCV_MCU_DMA_OK && dma_completion_status == 0u) {
    __asm__ volatile ("wfi");
  }
  if (dma_completion_status != ERISCV_MCU_DMA_STATUS_DONE) {
    result = ERISCV_MCU_DMA_EIO;
  }
  for (index = 0u; result == ERISCV_MCU_DMA_OK && index < DMA_WORDS; ++index) {
    if (destination[index] != source[index]) {
      result = ERISCV_MCU_DMA_EIO;
    }
  }
  eriscv_mcu_gpio_write(result == ERISCV_MCU_DMA_OK ? 1u : (eriscv_mcu_u32)(-result));
  eriscv_mcu_uart_puts(result == ERISCV_MCU_DMA_OK ?
                      "eRISCV-M2 DMA IRQ WFI PASS\n" : "eRISCV-M2 DMA IRQ WFI FAIL\n");
  for (;;) {
  }
}
