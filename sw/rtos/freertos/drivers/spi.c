/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "spi.h"

#include "plic.h"

#define SPI_TXDATA 0x00u
#define SPI_RXDATA 0x04u
#define SPI_STATUS 0x08u
#define SPI_CLKDIV 0x0cu
#define SPI_CTRL   0x10u
#define SPI_SS     0x14u

#define SPI_CTRL_ENABLE (1u << 0)
#define SPI_CTRL_IRQ    (1u << 1)
#define SPI_CTRL_DONE   (1u << 4)
#define SPI_STATUS_BUSY (1u << 1)
#define SPI_STATUS_DONE (1u << 3)
#define SPI_MODE_MASK   (FREERTOS_SPI_CTRL_CPOL | FREERTOS_SPI_CTRL_CPHA |                          FREERTOS_SPI_CTRL_LSB)

#define SPI_OK       0
#define SPI_EINVAL  -1
#define SPI_EBUSY   -2
#define SPI_ETIMEOUT -3

static eriscv_mcu_u32 spi_control;
static volatile int spi_async_active;
static const eriscv_mcu_u8 *spi_async_tx;
static eriscv_mcu_u8 *spi_async_rx;
static size_t spi_async_length;
static volatile size_t spi_async_index;
static freertos_spi_callback_t spi_async_callback;
static void *spi_async_context;

static void spi_write_control(int irq, int clear_done)
{
  eriscv_mcu_u32 control = spi_control | SPI_CTRL_ENABLE;
  if (irq) {
    control |= SPI_CTRL_IRQ;
  }
  if (clear_done) {
    control |= SPI_CTRL_DONE;
  }
  eriscv_mcu_mmio_write32(ERISCV_MCU_SPI0_BASE + SPI_CTRL, control);
}

static int spi_wait_idle(eriscv_mcu_u32 timeout_cycles)
{
  while ((eriscv_mcu_mmio_read32(ERISCV_MCU_SPI0_BASE + SPI_STATUS) &
          SPI_STATUS_BUSY) != 0u) {
    if (timeout_cycles == 0u) {
      return SPI_ETIMEOUT;
    }
    --timeout_cycles;
  }
  return SPI_OK;
}

static void spi_clear_done(int irq)
{
  spi_write_control(irq, 1);
}

int freertos_spi_init(eriscv_mcu_u32 clock_divisor, eriscv_mcu_u32 control)
{
  if ((control & ~(SPI_MODE_MASK)) != 0u) {
    return SPI_EINVAL;
  }
  if (clock_divisor == 0u) {
    clock_divisor = 1u;
  }
  spi_control = control & SPI_MODE_MASK;
  spi_async_active = 0;
  spi_async_callback = (freertos_spi_callback_t)0;
  eriscv_mcu_mmio_write32(ERISCV_MCU_SPI0_BASE + SPI_CLKDIV, clock_divisor);
  spi_write_control(0, 1);
  eriscv_mcu_mmio_write32(ERISCV_MCU_SPI0_BASE + SPI_SS, 0xfu);
  freertos_plic_init_source(ERISCV_MCU_SPI0_PLIC_SOURCE, 1u);
  return SPI_OK;
}

int freertos_spi_select(eriscv_mcu_u32 slave)
{
  if (slave >= 4u) {
    return SPI_EINVAL;
  }
  eriscv_mcu_mmio_write32(ERISCV_MCU_SPI0_BASE + SPI_SS,
                           (~(1u << slave)) & 0xfu);
  return SPI_OK;
}

int freertos_spi_transfer_buf(eriscv_mcu_u32 slave,
                              const eriscv_mcu_u8 *tx,
                              eriscv_mcu_u8 *rx,
                              size_t length,
                              eriscv_mcu_u32 timeout_cycles)
{
  size_t index;
  int result;

  if (length == 0u || spi_async_active != 0) {
    return length == 0u ? SPI_EINVAL : SPI_EBUSY;
  }
  result = freertos_spi_select(slave);
  if (result != SPI_OK) {
    return result;
  }
  for (index = 0; index < length; ++index) {
    eriscv_mcu_mmio_write32(ERISCV_MCU_SPI0_BASE + SPI_TXDATA,
                             tx != (const eriscv_mcu_u8 *)0 ? tx[index] : 0xffu);
    result = spi_wait_idle(timeout_cycles);
    if (result != SPI_OK) {
      eriscv_mcu_mmio_write32(ERISCV_MCU_SPI0_BASE + SPI_SS, 0xfu);
      return result;
    }
    if (rx != (eriscv_mcu_u8 *)0) {
      rx[index] = (eriscv_mcu_u8)eriscv_mcu_mmio_read32(
          ERISCV_MCU_SPI0_BASE + SPI_RXDATA);
    }
    spi_clear_done(0);
  }
  eriscv_mcu_mmio_write32(ERISCV_MCU_SPI0_BASE + SPI_SS, 0xfu);
  return SPI_OK;
}

int freertos_spi_transfer(eriscv_mcu_u8 tx, eriscv_mcu_u8 *rx,
                          eriscv_mcu_u32 timeout_cycles)
{
  return freertos_spi_transfer_buf(0u, &tx, rx, 1u, timeout_cycles);
}

int freertos_spi_start_async(eriscv_mcu_u32 slave,
                             const eriscv_mcu_u8 *tx,
                             eriscv_mcu_u8 *rx,
                             size_t length,
                             freertos_spi_callback_t callback,
                             void *context)
{
  if (length == 0u || callback == (freertos_spi_callback_t)0) {
    return SPI_EINVAL;
  }
  if (spi_async_active != 0) {
    return SPI_EBUSY;
  }
  if (freertos_spi_select(slave) != SPI_OK) {
    return SPI_EINVAL;
  }
  spi_async_tx = tx;
  spi_async_rx = rx;
  spi_async_length = length;
  spi_async_index = 0u;
  spi_async_callback = callback;
  spi_async_context = context;
  spi_async_active = 1;
  spi_write_control(1, 1);
  eriscv_mcu_mmio_write32(ERISCV_MCU_SPI0_BASE + SPI_TXDATA,
                           tx != (const eriscv_mcu_u8 *)0 ? tx[0] : 0xffu);
  return SPI_OK;
}

void freertos_spi_irq_handler(void)
{
  eriscv_mcu_u8 value;
  freertos_spi_callback_t callback;
  void *context;

  if ((eriscv_mcu_mmio_read32(ERISCV_MCU_SPI0_BASE + SPI_STATUS) &
       SPI_STATUS_DONE) == 0u) {
    return;
  }
  if (spi_async_active == 0) {
    spi_clear_done(0);
    return;
  }
  value = (eriscv_mcu_u8)eriscv_mcu_mmio_read32(
      ERISCV_MCU_SPI0_BASE + SPI_RXDATA);
  if (spi_async_rx != (eriscv_mcu_u8 *)0) {
    spi_async_rx[spi_async_index] = value;
  }
  spi_clear_done(1);
  ++spi_async_index;
  if (spi_async_index < spi_async_length) {
    eriscv_mcu_mmio_write32(
        ERISCV_MCU_SPI0_BASE + SPI_TXDATA,
        spi_async_tx != (const eriscv_mcu_u8 *)0 ?
            spi_async_tx[spi_async_index] : 0xffu);
    return;
  }
  spi_async_active = 0;
  eriscv_mcu_mmio_write32(ERISCV_MCU_SPI0_BASE + SPI_SS, 0xfu);
  spi_write_control(0, 0);
  callback = spi_async_callback;
  context = spi_async_context;
  spi_async_callback = (freertos_spi_callback_t)0;
  spi_async_context = (void *)0;
  callback(SPI_OK, context);
}

int freertos_spi_irq_pending(void)
{
  return (eriscv_mcu_mmio_read32(ERISCV_MCU_SPI0_BASE + SPI_STATUS) &
          SPI_STATUS_DONE) != 0u;
}
