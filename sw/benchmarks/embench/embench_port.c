/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "support.h"

#include "eriscv_mcu.h"

volatile unsigned int eriscv_embench_result;
static unsigned int start_mcycle;
static unsigned int stop_mcycle;

static unsigned int read_mcycle(void) {
  unsigned int value;

  __asm__ volatile ("csrr %0, mcycle" : "=r"(value));
  return value;
}

void initialise_board(void) {
	eriscv_mcu_uart_init(ERISCV_MCU_UART_DIVISOR);
  eriscv_embench_result = 0u;
}

void start_trigger(void) {
  start_mcycle = read_mcycle();
}

void stop_trigger(void) {
  stop_mcycle = read_mcycle();
}

int main(void) {
  int result;
  int correct;

  initialise_board();
  initialise_benchmark();
  warm_caches(WARMUP_HEAT);
  start_trigger();
  result = benchmark();
  stop_trigger();
  correct = verify_benchmark(result);
  eriscv_embench_result = (correct != 0 ? 0x80000000u : 0x40000000u) |
                          ((stop_mcycle - start_mcycle) & 0x3fffffffu);
  for (;;) {
  }
}
