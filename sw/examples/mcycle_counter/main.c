/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "eriscv_mcu.h"

#define MCYCLE_COUNTER_MAGIC 0x4d435931u
#define MCYCLE_COUNTER_PASS  0x80000001u
#define MCYCLE_COUNTER_FAIL  0x40000001u
#define MCYCLE_NOP_COUNT     8192u

typedef struct {
  volatile eriscv_mcu_u32 done;
  eriscv_mcu_u32 magic;
  eriscv_mcu_u32 nop_count;
  eriscv_mcu_u32 start;
  eriscv_mcu_u32 middle;
  eriscv_mcu_u32 stop;
  eriscv_mcu_u32 first_delta;
  eriscv_mcu_u32 second_delta;
} mcycle_counter_report_t;

volatile mcycle_counter_report_t eriscv_mcycle_counter_report;

static eriscv_mcu_u32 read_mcycle(void) {
  eriscv_mcu_u32 value;

  __asm__ volatile ("csrr %0, mcycle" : "=r"(value) :: "memory");
  return value;
}

__attribute__((noinline)) static void execute_nops(void) {
  __asm__ volatile (
      ".rept 8192\n"
      "nop\n"
      ".endr\n"
      ::: "memory");
}

int main(void) {
  eriscv_mcu_u32 first_delta;
  eriscv_mcu_u32 second_delta;

  eriscv_mcycle_counter_report.done = 0u;
  eriscv_mcycle_counter_report.magic = MCYCLE_COUNTER_MAGIC;
  eriscv_mcycle_counter_report.nop_count = MCYCLE_NOP_COUNT;

  eriscv_mcycle_counter_report.start = read_mcycle();
  execute_nops();
  eriscv_mcycle_counter_report.middle = read_mcycle();
  execute_nops();
  eriscv_mcycle_counter_report.stop = read_mcycle();

  first_delta = eriscv_mcycle_counter_report.middle -
                eriscv_mcycle_counter_report.start;
  second_delta = eriscv_mcycle_counter_report.stop -
                 eriscv_mcycle_counter_report.middle;
  eriscv_mcycle_counter_report.first_delta = first_delta;
  eriscv_mcycle_counter_report.second_delta = second_delta;
  eriscv_mcycle_counter_report.done =
      (first_delta >= MCYCLE_NOP_COUNT && second_delta >= MCYCLE_NOP_COUNT) ?
      MCYCLE_COUNTER_PASS : MCYCLE_COUNTER_FAIL;

  return 0;
}
