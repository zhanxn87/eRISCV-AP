/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "eriscv_mcu.h"

static const char message[] =
    "eRISCV MCU async UART IRQ FIFO smoke: "
    "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ\r\n";

int main(void) {
  eriscv_mcu_u32 length = (eriscv_mcu_u32)(sizeof(message) - 1u);

	eriscv_mcu_uart_async_init(ERISCV_MCU_UART_DIVISOR);
  if (eriscv_mcu_uart_async_write(message, length) != length) {
    eriscv_mcu_gpio_set_direction(1u);
    eriscv_mcu_gpio_write(2u);
    for (;;) {
    }
  }

  while (eriscv_mcu_uart_async_tx_pending()) {
  }

  eriscv_mcu_gpio_set_direction(1u);
  eriscv_mcu_gpio_write(1u);
  for (;;) {
  }
}
