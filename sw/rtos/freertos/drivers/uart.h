/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#ifndef ERISCV_FREERTOS_UART_H
#define ERISCV_FREERTOS_UART_H

#include "eriscv_mcu.h"

void eriscv_mcu_uart_init(eriscv_mcu_u32 baud_divisor);
void eriscv_mcu_uart_putc(char ch);
void eriscv_mcu_uart_puts(const char *text);
int eriscv_mcu_uart_getc(void);
void eriscv_mcu_uart_async_init(eriscv_mcu_u32 baud_divisor);
int eriscv_mcu_uart_async_putc(char ch);
eriscv_mcu_u32 eriscv_mcu_uart_async_write(const char *data, eriscv_mcu_u32 length);
int eriscv_mcu_uart_async_getc(void);
int eriscv_mcu_uart_async_tx_pending(void);
eriscv_mcu_u32 eriscv_mcu_uart_async_rx_dropped(void);
void eriscv_mcu_uart_irq_handler(void);

#endif
