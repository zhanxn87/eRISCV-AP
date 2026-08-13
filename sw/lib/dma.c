/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "eriscv_mcu.h"

static int dma_range_valid(eriscv_mcu_u32 address, eriscv_mcu_u32 length)
{
  if (length == 0u || length > ERISCV_MCU_SYSTEM_SRAM_SIZE) {
    return 0;
  }
  if (address < ERISCV_MCU_SYSTEM_SRAM_BASE) {
    return 0;
  }
  return (address - ERISCV_MCU_SYSTEM_SRAM_BASE) <=
         (ERISCV_MCU_SYSTEM_SRAM_SIZE - length);
}

int eriscv_mcu_dma_start(eriscv_mcu_u32 source, eriscv_mcu_u32 destination,
                         eriscv_mcu_u32 length, int irq_enable)
{
  eriscv_mcu_u32 control = ERISCV_MCU_DMA_CTRL_START;

  if (((source | destination | length) & 3u) != 0u ||
      !dma_range_valid(source, length) || !dma_range_valid(destination, length)) {
    return ERISCV_MCU_DMA_EINVAL;
  }
  if ((eriscv_mcu_dma_status() & ERISCV_MCU_DMA_STATUS_BUSY) != 0u) {
    return ERISCV_MCU_DMA_EBUSY;
  }
  eriscv_mcu_dma_clear_status();
  eriscv_mcu_mmio_write32(ERISCV_MCU_DMA_BASE + ERISCV_MCU_DMA_SRC, source);
  eriscv_mcu_mmio_write32(ERISCV_MCU_DMA_BASE + ERISCV_MCU_DMA_DST, destination);
  eriscv_mcu_mmio_write32(ERISCV_MCU_DMA_BASE + ERISCV_MCU_DMA_LEN, length);
  if (irq_enable != 0) {
    control |= ERISCV_MCU_DMA_CTRL_IRQ_EN;
  }
  eriscv_mcu_mmio_write32(ERISCV_MCU_DMA_BASE + ERISCV_MCU_DMA_CTRL, control);
  return ERISCV_MCU_DMA_OK;
}

int eriscv_mcu_dma_uart_tx_start(eriscv_mcu_u32 source, eriscv_mcu_u32 length,
                                 int irq_enable)
{
  eriscv_mcu_u32 control = ERISCV_MCU_DMA_CTRL_START | ERISCV_MCU_DMA_CTRL_UART_TX;

  if ((source & 3u) != 0u || !dma_range_valid(source, length)) {
    return ERISCV_MCU_DMA_EINVAL;
  }
  if ((eriscv_mcu_dma_status() & ERISCV_MCU_DMA_STATUS_BUSY) != 0u) {
    return ERISCV_MCU_DMA_EBUSY;
  }
  eriscv_mcu_dma_clear_status();
  eriscv_mcu_mmio_write32(ERISCV_MCU_DMA_BASE + ERISCV_MCU_DMA_SRC, source);
  eriscv_mcu_mmio_write32(ERISCV_MCU_DMA_BASE + ERISCV_MCU_DMA_DST, ERISCV_MCU_UART0_BASE);
  eriscv_mcu_mmio_write32(ERISCV_MCU_DMA_BASE + ERISCV_MCU_DMA_LEN, length);
  if (irq_enable != 0) {
    control |= ERISCV_MCU_DMA_CTRL_IRQ_EN;
  }
  eriscv_mcu_mmio_write32(ERISCV_MCU_DMA_BASE + ERISCV_MCU_DMA_CTRL, control);
  return ERISCV_MCU_DMA_OK;
}

int eriscv_mcu_dma_start_descriptor(volatile eriscv_mcu_dma_descriptor_t *head,
                                    int irq_enable)
{
  eriscv_mcu_u32 address = (eriscv_mcu_u32)(unsigned long)head;
  eriscv_mcu_u32 control = ERISCV_MCU_DMA_CTRL_DESC_START;

  if ((address & (ERISCV_MCU_DMA_DESCRIPTOR_ALIGN - 1u)) != 0u ||
      !dma_range_valid(address, ERISCV_MCU_DMA_DESCRIPTOR_SIZE)) {
    return ERISCV_MCU_DMA_EINVAL;
  }
  if ((eriscv_mcu_dma_status() & ERISCV_MCU_DMA_STATUS_BUSY) != 0u) {
    return ERISCV_MCU_DMA_EBUSY;
  }
  eriscv_mcu_dma_clear_status();
  __asm__ volatile ("fence rw, rw" ::: "memory");
  eriscv_mcu_mmio_write32(ERISCV_MCU_DMA_BASE + ERISCV_MCU_DMA_DESC_HEAD, address);
  if (irq_enable != 0) {
    control |= ERISCV_MCU_DMA_CTRL_IRQ_EN;
  }
  eriscv_mcu_mmio_write32(ERISCV_MCU_DMA_BASE + ERISCV_MCU_DMA_CTRL, control);
  return ERISCV_MCU_DMA_OK;
}

eriscv_mcu_u32 eriscv_mcu_dma_status(void)
{
  return eriscv_mcu_mmio_read32(ERISCV_MCU_DMA_BASE + ERISCV_MCU_DMA_STATUS);
}

int eriscv_mcu_dma_wait(eriscv_mcu_u32 timeout_polls)
{
  eriscv_mcu_u32 status;

  do {
    status = eriscv_mcu_dma_status();
    if ((status & ERISCV_MCU_DMA_STATUS_BUSY) == 0u) {
      return (status & ERISCV_MCU_DMA_STATUS_ERROR) != 0u ?
          ERISCV_MCU_DMA_EIO : ERISCV_MCU_DMA_OK;
    }
  } while (timeout_polls-- != 0u);
  return ERISCV_MCU_DMA_ETIMEOUT;
}

void eriscv_mcu_dma_clear_status(void)
{
  eriscv_mcu_mmio_write32(ERISCV_MCU_DMA_BASE + ERISCV_MCU_DMA_STATUS,
                          ERISCV_MCU_DMA_STATUS_DONE | ERISCV_MCU_DMA_STATUS_ERROR |
                          ERISCV_MCU_DMA_STATUS_DESC_IRQ);
}

void eriscv_mcu_dma_irq_enable(eriscv_mcu_u32 priority)
{
  eriscv_mcu_plic_set_priority(ERISCV_MCU_DMA_PLIC_SOURCE, priority);
  eriscv_mcu_plic_set_enabled(ERISCV_MCU_DMA_PLIC_SOURCE, 1);
  eriscv_mcu_plic_set_threshold(0u);
}

void eriscv_mcu_dma_irq_disable(void)
{
  eriscv_mcu_plic_set_enabled(ERISCV_MCU_DMA_PLIC_SOURCE, 0);
}

__attribute__((weak)) void eriscv_mcu_dma_complete_handler(eriscv_mcu_u32 status)
{
  (void)status;
}

void eriscv_mcu_dma_irq_handler(void)
{
  eriscv_mcu_u32 status = eriscv_mcu_dma_status();

  eriscv_mcu_dma_clear_status();
  eriscv_mcu_dma_complete_handler(status);
}
