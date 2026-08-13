/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "eriscv_mcu.h"

/* Multi-source interrupt demo: CLINT timer (toggles GPIO) + UART RX (echo).
 * Overrides the full trap handler to demonstrate dispatch. */

static volatile eriscv_mcu_u32 g_tick = 0u;
#define TICK_INTERVAL 500000u

/* --- Custom ISRs --- */
void eriscv_mcu_timer_irq_handler(void) {
  eriscv_mcu_u64 now = eriscv_mcu_clint_read_mtime();
  eriscv_mcu_clint_set_mtimecmp(now + TICK_INTERVAL);
  ++g_tick;
}

/* UART RX is dispatched through the standard external IRQ path. */

/* --- Custom trap handler (replaces weak default) --- */
eriscv_mcu_u32 eriscv_mcu_trap_handler(eriscv_mcu_u32 mcause,
                                        eriscv_mcu_u32 mepc,
                                        eriscv_mcu_u32 mtval) {
  (void)mtval;
  if ((mcause & ERISCV_MCU_MCAUSE_INTERRUPT) == 0u) {
    /* Not an interrupt -- spin on unexpected exceptions. */
    for (;;) {}
  }
  eriscv_mcu_u32 code = mcause & ERISCV_MCU_MCAUSE_CODE_MASK;
  if (code == ERISCV_MCU_MCAUSE_MEI) {
    eriscv_mcu_u32 src = eriscv_mcu_plic_claim();
    if (src == ERISCV_MCU_UART0_PLIC_SOURCE) {
      /* Echo received byte. */
      int ch = eriscv_mcu_uart_getc();
      if (ch >= 0) eriscv_mcu_uart_putc((char)ch);
    }
    if (src != 0u) eriscv_mcu_plic_complete(src);
    return mepc;
  }
  if (code == ERISCV_MCU_MCAUSE_MTI) {
    eriscv_mcu_timer_irq_handler();
    return mepc;
  }
  /* Unhandled interrupt -- spin. */
  for (;;) {}
}

/* --- Main --- */
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

  eriscv_mcu_uart_puts("Multi-source IRQ: timer toggles GPIO, UART RX echoes\n");
  eriscv_mcu_uart_puts("Type characters to see echo; timer blinks bit 0.\n");

  /* Arm timer. */
  eriscv_mcu_clint_set_mtimecmp(eriscv_mcu_clint_read_mtime() + TICK_INTERVAL);
  /* Enable UART RX interrupt (PLIC source 1 already routed through MEI). */
  eriscv_mcu_plic_set_priority(ERISCV_MCU_UART0_PLIC_SOURCE, 1u);
  eriscv_mcu_plic_set_enabled(ERISCV_MCU_UART0_PLIC_SOURCE, 1);
  eriscv_mcu_plic_set_threshold(0u);

  eriscv_mcu_enable_machine_irqs(ERISCV_MCU_MIE_MTIE | ERISCV_MCU_MIE_MEIE);

  for (;;) {
    /* Blink GPIO on timer ticks in foreground. */
    eriscv_mcu_u32 last = g_tick;
    while (g_tick == last) { __asm__ volatile ("wfi"); }
    eriscv_mcu_gpio_write(g_tick & 1u);
    eriscv_mcu_uart_puts("[timer ");
    uart_print_dec(g_tick);
    eriscv_mcu_uart_puts("]\n");
  }
}
