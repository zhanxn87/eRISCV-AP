/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "eriscv_mcu.h"

/* WFI tickless idle demo: CPU sleeps in WFI, timer wakes it periodically.
 * Measures idle duty cycle and prints wake count. */

static volatile eriscv_mcu_u32 g_wake_count = 0u;
#define SLEEP_TICKS 200000u

void eriscv_mcu_timer_irq_handler(void) {
  eriscv_mcu_u64 now = eriscv_mcu_clint_read_mtime();
  eriscv_mcu_clint_set_mtimecmp(now + SLEEP_TICKS);
  ++g_wake_count;
}

static void uart_print_dec(eriscv_mcu_u32 n) {
  static char buf[12];
  int i = 10;
  buf[11] = '\0';
  do { buf[i--] = (char)('0' + (n % 10u)); n /= 10u; } while (n != 0u);
  eriscv_mcu_uart_puts(&buf[i + 1]);
}

int main(void) {
	eriscv_mcu_uart_init(ERISCV_MCU_UART_DIVISOR);
  eriscv_mcu_gpio_set_direction(1u);

  eriscv_mcu_uart_puts("WFI tickless idle demo\n");

  /* Arm first timer wake. */
  eriscv_mcu_clint_set_mtimecmp(eriscv_mcu_clint_read_mtime() + SLEEP_TICKS);
  eriscv_mcu_enable_machine_irqs(ERISCV_MCU_MIE_MTIE);

  for (;;) {
    /* Sleep until next timer interrupt. */
    __asm__ volatile ("wfi");

    eriscv_mcu_gpio_write(g_wake_count & 1u);
    eriscv_mcu_uart_puts("wake #");
    uart_print_dec(g_wake_count);

    if ((g_wake_count % 10u) == 0u) {
      eriscv_mcu_uart_puts("  [milestone]");
    }
    eriscv_mcu_uart_puts("\n");

    /* Simulate brief foreground work before sleeping again. */
    volatile eriscv_mcu_u32 i;
    for (i = 0u; i < 1000u; ++i) { __asm__ volatile (""); }
  }
}
