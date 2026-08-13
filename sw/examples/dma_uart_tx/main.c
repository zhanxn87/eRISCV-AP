/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "eriscv_mcu.h"

static volatile eriscv_mcu_u8 dma_text[17] ERISCV_MCU_SYSTEM_SRAM_BUFFER;
static const eriscv_mcu_u8 expected_text[] = "DMA UART TX PASS\n";

int main(void)
{
  eriscv_mcu_u32 index;
  int result;

	eriscv_mcu_uart_init(ERISCV_MCU_UART_DIVISOR);
  eriscv_mcu_gpio_set_direction(1u);
  for (index = 0u; index < sizeof(dma_text); ++index) {
    dma_text[index] = expected_text[index];
  }
  __asm__ volatile ("fence rw, rw" ::: "memory");
  result = eriscv_mcu_dma_uart_tx_start((eriscv_mcu_u32)(unsigned long)dma_text,
                                        sizeof(dma_text), 0);
  if (result == ERISCV_MCU_DMA_OK) {
    result = eriscv_mcu_dma_wait(20000u);
  }
  eriscv_mcu_gpio_write(result == ERISCV_MCU_DMA_OK ? 1u : (eriscv_mcu_u32)(-result));
  if (result != ERISCV_MCU_DMA_OK) {
    eriscv_mcu_uart_puts("DMA UART TX FAIL\n");
  }
  for (;;) {
  }
}
