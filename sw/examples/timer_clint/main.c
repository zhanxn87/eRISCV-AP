/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "eriscv_mcu.h"

/* CLINT periodic timer interrupt -- toggles GPIO bit 0 every tick. */

static volatile eriscv_mcu_u32 g_tick = 0u;
#define TICK_INTERVAL 100000u  /* ~100k CLINT ticks between interrupts */

/* Override the weak timer IRQ handler. */
void eriscv_mcu_timer_irq_handler(void) {
  eriscv_mcu_u64 now = eriscv_mcu_clint_read_mtime();
  eriscv_mcu_clint_set_mtimecmp(now + TICK_INTERVAL);
  ++g_tick;
}

static void uart_print_dec(eriscv_mcu_u32 n) {
  static char buf[12];
  int i = 10;
  buf[11] = '\0';
  do {
    buf[i--] = (char)('0' + (n % 10u));
    n /= 10u;
  } while (n != 0u);
  eriscv_mcu_uart_puts(&buf[i + 1]);
}

int main(void) {
	eriscv_mcu_uart_init(ERISCV_MCU_UART_DIVISOR);
  eriscv_mcu_gpio_set_direction(1u);

  eriscv_mcu_uart_puts("CLINT timer IRQ demo -- tick every ~100k cycles\n");

  /* Arm first timer interrupt. */
  eriscv_mcu_clint_set_mtimecmp(eriscv_mcu_clint_read_mtime() + TICK_INTERVAL);
  eriscv_mcu_enable_machine_irqs(ERISCV_MCU_MIE_MTIE);

  for (;;) {
    eriscv_mcu_u32 last = g_tick;
    while (g_tick == last) {
      __asm__ volatile ("wfi");
    }
    eriscv_mcu_gpio_write(g_tick & 1u);
    eriscv_mcu_uart_puts("tick ");
    uart_print_dec(g_tick);
    eriscv_mcu_uart_puts("\n");
  }
}
