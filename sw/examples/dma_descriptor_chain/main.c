/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "eriscv_mcu.h"

#define DMA_WORDS 2u

static volatile eriscv_mcu_u32 source_a[DMA_WORDS] ERISCV_MCU_SYSTEM_SRAM_BUFFER;
static volatile eriscv_mcu_u32 source_b[DMA_WORDS] ERISCV_MCU_SYSTEM_SRAM_BUFFER;
static volatile eriscv_mcu_u32 destination_a[DMA_WORDS] ERISCV_MCU_SYSTEM_SRAM_BUFFER;
static volatile eriscv_mcu_u32 destination_b[DMA_WORDS] ERISCV_MCU_SYSTEM_SRAM_BUFFER;
static volatile eriscv_mcu_dma_descriptor_t descriptor[2] ERISCV_MCU_DMA_DESCRIPTOR;

int main(void)
{
  eriscv_mcu_u32 index;
  int result;

	eriscv_mcu_uart_init(ERISCV_MCU_UART_DIVISOR);
  eriscv_mcu_gpio_set_direction(1u);
  for (index = 0u; index < DMA_WORDS; ++index) {
    source_a[index] = 0xa5a50000u + index;
    source_b[index] = 0x5a5a0000u + index;
    destination_a[index] = 0u;
    destination_b[index] = 0u;
  }

  descriptor[0].next = (eriscv_mcu_u32)(unsigned long)&descriptor[1];
  descriptor[0].source = (eriscv_mcu_u32)(unsigned long)source_a;
  descriptor[0].destination = (eriscv_mcu_u32)(unsigned long)destination_a;
  descriptor[0].length = DMA_WORDS * sizeof(source_a[0]);
  descriptor[0].status = 0u;
  descriptor[0].bytes_transferred = 0u;
  descriptor[0].reserved = 0u;
  descriptor[1].next = 0u;
  descriptor[1].source = (eriscv_mcu_u32)(unsigned long)source_b;
  descriptor[1].destination = (eriscv_mcu_u32)(unsigned long)destination_b;
  descriptor[1].length = DMA_WORDS * sizeof(source_b[0]);
  descriptor[1].status = 0u;
  descriptor[1].bytes_transferred = 0u;
  descriptor[1].reserved = 0u;
  __asm__ volatile ("fence rw, rw" ::: "memory");
  descriptor[0].control = ERISCV_MCU_DMA_DESC_CTRL_OWN |
                          ERISCV_MCU_DMA_DESC_CTRL_SRC_INC |
                          ERISCV_MCU_DMA_DESC_CTRL_DST_INC;
  descriptor[1].control = ERISCV_MCU_DMA_DESC_CTRL_OWN |
                          ERISCV_MCU_DMA_DESC_CTRL_END |
                          ERISCV_MCU_DMA_DESC_CTRL_SRC_INC |
                          ERISCV_MCU_DMA_DESC_CTRL_DST_INC;

  result = eriscv_mcu_dma_start_descriptor(&descriptor[0], 0);
  if (result == ERISCV_MCU_DMA_OK) {
    result = eriscv_mcu_dma_wait(10000u);
  }
  for (index = 0u; result == ERISCV_MCU_DMA_OK && index < DMA_WORDS; ++index) {
    if (destination_a[index] != source_a[index] || destination_b[index] != source_b[index]) {
      result = ERISCV_MCU_DMA_EIO;
    }
  }
  if (descriptor[0].control != (ERISCV_MCU_DMA_DESC_CTRL_SRC_INC |
                                ERISCV_MCU_DMA_DESC_CTRL_DST_INC) ||
      descriptor[1].control != (ERISCV_MCU_DMA_DESC_CTRL_END |
                                ERISCV_MCU_DMA_DESC_CTRL_SRC_INC |
                                ERISCV_MCU_DMA_DESC_CTRL_DST_INC) ||
      descriptor[0].status != ERISCV_MCU_DMA_DESC_STATUS_DONE ||
      descriptor[1].status != ERISCV_MCU_DMA_DESC_STATUS_DONE) {
    result = ERISCV_MCU_DMA_EIO;
  }
  eriscv_mcu_gpio_write(result == ERISCV_MCU_DMA_OK ? 1u : (eriscv_mcu_u32)(-result));
  eriscv_mcu_uart_puts(result == ERISCV_MCU_DMA_OK ?
                      "eRISCV-M2 DMA descriptor PASS\n" : "eRISCV-M2 DMA descriptor FAIL\n");
  for (;;) {
  }
}
