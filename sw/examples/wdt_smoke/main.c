/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "eriscv_mcu.h"

/* WDT smoke: enable watchdog, feed several times, then stop feeding.
 * After timeout, WDT asserts wdt_rst_n → SoC resets.
 * GPIO bit 0 toggled on each feed; last toggle before timeout visible in sim. */

int main(void) {
	eriscv_mcu_uart_init(ERISCV_MCU_UART_DIVISOR);
  eriscv_mcu_gpio_set_direction(1u);

  eriscv_mcu_uart_puts("WDT smoke: enable, feed 3x, then stop\n");

  /* Set 500k cycle timeout, feed every ~50k cycles. */
  eriscv_mcu_wdt_set_timeout(500000u);
  eriscv_mcu_wdt_set_pretimeout(50000u); /* early warning before final reset */
  eriscv_mcu_wdt_set_window(0u);     /* no window — feed anytime */
  eriscv_mcu_wdt_enable(1);          /* enable with pre-timeout IRQ */

  /* Feed 1 */
  eriscv_mcu_wdt_feed();
  eriscv_mcu_gpio_write(1u);
  eriscv_mcu_uart_puts("  feed 1\n");

  /* Busy-wait ~50k cycles */
  volatile eriscv_mcu_u32 i;
  for (i = 0u; i < 1000u; ++i) { __asm__ volatile (""); }

  /* Feed 2 */
  eriscv_mcu_wdt_feed();
  eriscv_mcu_gpio_write(0u);
  eriscv_mcu_uart_puts("  feed 2\n");

  for (i = 0u; i < 1000u; ++i) { __asm__ volatile (""); }

  /* Feed 3 */
  eriscv_mcu_wdt_feed();
  eriscv_mcu_gpio_write(1u);
  eriscv_mcu_uart_puts("  feed 3 — stopping feeds, expect reset\n");

  /* Now stop feeding. WDT will expire in ~500k cycles, assert wdt_rst_n,
   * and the SoC will reset. This is the intended test end. */
  for (;;) { __asm__ volatile (""); }
}
