/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "eriscv_mcu.h"

int main(void) {
	eriscv_mcu_uart_init(ERISCV_MCU_UART_DIVISOR);
  eriscv_mcu_uart_puts("eRISCV MCU BSP hello\n");

  eriscv_mcu_gpio_set_direction(1u);
  eriscv_mcu_gpio_write(1u);
  for (;;) {
  }
}
