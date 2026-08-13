/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#ifndef ERISCV_FREERTOS_SPI_H
#define ERISCV_FREERTOS_SPI_H

#include <stddef.h>

#include "eriscv_mcu.h"

#define FREERTOS_SPI_CTRL_CPOL   (1u << 2)
#define FREERTOS_SPI_CTRL_CPHA   (1u << 3)
#define FREERTOS_SPI_CTRL_LSB    (1u << 5)

typedef void (*freertos_spi_callback_t)(int result, void *context);

int freertos_spi_init(eriscv_mcu_u32 clock_divisor, eriscv_mcu_u32 control);
int freertos_spi_select(eriscv_mcu_u32 slave);
int freertos_spi_transfer(eriscv_mcu_u8 tx, eriscv_mcu_u8 *rx,
                          eriscv_mcu_u32 timeout_cycles);
int freertos_spi_transfer_buf(eriscv_mcu_u32 slave,
                              const eriscv_mcu_u8 *tx,
                              eriscv_mcu_u8 *rx,
                              size_t length,
                              eriscv_mcu_u32 timeout_cycles);
int freertos_spi_start_async(eriscv_mcu_u32 slave,
                             const eriscv_mcu_u8 *tx,
                             eriscv_mcu_u8 *rx,
                             size_t length,
                             freertos_spi_callback_t callback,
                             void *context);
void freertos_spi_irq_handler(void);
int freertos_spi_irq_pending(void);

#endif
