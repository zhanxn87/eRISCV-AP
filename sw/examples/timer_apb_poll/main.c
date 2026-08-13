/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "eriscv_mcu.h"

/* APB Timer0 polling -- one-shot countdown, no interrupts. */

int main(void) {
	eriscv_mcu_uart_init(ERISCV_MCU_UART_DIVISOR);
  eriscv_mcu_gpio_set_direction(1u);
  eriscv_mcu_gpio_write(0u);

  eriscv_mcu_uart_puts("APB Timer poll demo -- 3 one-shot intervals\n");

  /* Interval 1: short */
  eriscv_mcu_timer_start(50000u, 0);
  while (!eriscv_mcu_timer_expired()) {}
  eriscv_mcu_gpio_write(1u);
  eriscv_mcu_uart_puts("  [1] 50k ticks elapsed\n");

  /* Interval 2: medium */
  eriscv_mcu_timer_start(200000u, 0);
  while (!eriscv_mcu_timer_expired()) {}
  eriscv_mcu_gpio_write(0u);
  eriscv_mcu_uart_puts("  [2] 200k ticks elapsed\n");

  /* Interval 3: long */
  eriscv_mcu_timer_start(500000u, 0);
  while (!eriscv_mcu_timer_expired()) {}
  eriscv_mcu_gpio_write(1u);
  eriscv_mcu_uart_puts("  [3] 500k ticks elapsed -- PASS\n");

  for (;;) {}
}
