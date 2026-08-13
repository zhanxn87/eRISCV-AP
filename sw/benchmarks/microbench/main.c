/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "eriscv_mcu.h"

#define ITERATIONS 256u
#define REPORT_MAGIC 0x4d425031u

typedef struct {
  volatile eriscv_mcu_u32 done;
  eriscv_mcu_u32 magic;
  eriscv_mcu_u32 iterations;
  eriscv_mcu_u32 alu_cycles;
  eriscv_mcu_u32 branch_cycles;
  eriscv_mcu_u32 load_store_cycles;
  eriscv_mcu_u32 mul_cycles;
  eriscv_mcu_u32 div_cycles;
  eriscv_mcu_u32 fence_i_cycles;
  eriscv_mcu_u32 ecall_cycles;
  eriscv_mcu_u32 clint_wake_cycles;
  eriscv_mcu_u32 plic_service_cycles;
  eriscv_mcu_u32 alu_instructions;
  eriscv_mcu_u32 branch_instructions;
  eriscv_mcu_u32 load_store_instructions;
  eriscv_mcu_u32 mul_instructions;
  eriscv_mcu_u32 div_instructions;
  eriscv_mcu_u32 fence_i_instructions;
  eriscv_mcu_u32 work_signature;
} microbench_report_t;

volatile microbench_report_t eriscv_microbench_report;
static volatile eriscv_mcu_u32 work_buffer[64];
static volatile eriscv_mcu_u32 trap_done;
static volatile eriscv_mcu_u32 trap_stop;
static volatile eriscv_mcu_u32 timer_done;
static volatile eriscv_mcu_u32 timer_stop;
static volatile eriscv_mcu_u32 plic_done;
static volatile eriscv_mcu_u32 plic_stop;

static eriscv_mcu_u32 read_mcycle(void) {
  eriscv_mcu_u32 value;
  __asm__ volatile ("csrr %0, mcycle" : "=r"(value));
  return value;
}

static eriscv_mcu_u32 read_minstret(void) {
  eriscv_mcu_u32 value;
  __asm__ volatile ("csrr %0, minstret" : "=r"(value));
  return value;
}

__attribute__((noinline)) static void run_alu(void) {
  eriscv_mcu_u32 value = 1u;
  for (eriscv_mcu_u32 i = 0; i < ITERATIONS; ++i) {
    __asm__ volatile ("add %0, %0, %1" : "+r"(value) : "r"(i));
    __asm__ volatile ("xor %0, %0, %1" : "+r"(value) : "r"(i));
  }
  work_buffer[0] = value;
}

__attribute__((noinline)) static void run_branch(void) {
  eriscv_mcu_u32 value = 0u;
  for (eriscv_mcu_u32 i = 0; i < ITERATIONS; ++i) {
    if ((i & 1u) == 0u) value += i;
    else value ^= i;
  }
  work_buffer[1] = value;
}

__attribute__((noinline)) static void run_load_store(void) {
  for (eriscv_mcu_u32 i = 0; i < ITERATIONS; ++i) {
    work_buffer[i & 63u] = i;
    work_buffer[2] ^= work_buffer[i & 63u];
  }
}

__attribute__((noinline)) static void run_mul(void) {
  eriscv_mcu_u32 value = 3u;
  for (eriscv_mcu_u32 i = 1u; i <= ITERATIONS; ++i)
    __asm__ volatile ("mul %0, %0, %1" : "+r"(value) : "r"(i));
  work_buffer[3] = value;
}

__attribute__((noinline)) static void run_div(void) {
  eriscv_mcu_u32 value = 0x7fffffffu;
  for (eriscv_mcu_u32 i = 1u; i <= ITERATIONS; ++i) {
    __asm__ volatile ("divu %0, %0, %1" : "+r"(value) : "r"(i));
    value += 0x1020304u;
  }
  work_buffer[4] = value;
}

__attribute__((noinline)) static void run_fence_i(void) {
  for (eriscv_mcu_u32 i = 0; i < ITERATIONS; ++i)
    __asm__ volatile ("fence.i" ::: "memory");
}

void eriscv_mcu_timer_irq_handler(void) {
  timer_stop = read_mcycle();
  timer_done = 1u;
  eriscv_mcu_clint_set_mtimecmp(~0ull);
}

void eriscv_mcu_machine_external_irq_handler(void) {
  eriscv_mcu_u32 source = eriscv_mcu_plic_claim();
  if (source == ERISCV_MCU_TIMER0_PLIC_SOURCE) {
    plic_stop = read_mcycle();
    eriscv_mcu_mmio_write32(ERISCV_MCU_TIMER0_BASE + ERISCV_MCU_TIMER_CTRL, 0u);
    eriscv_mcu_mmio_write32(ERISCV_MCU_TIMER0_BASE + ERISCV_MCU_TIMER_STATUS, 1u);
    plic_done = 1u;
  }
  if (source != 0u) eriscv_mcu_plic_complete(source);
}

eriscv_mcu_u32 eriscv_mcu_trap_handler(eriscv_mcu_u32 mcause,
                                        eriscv_mcu_u32 mepc,
                                        eriscv_mcu_u32 mtval) {
  (void)mtval;
  if ((mcause & ERISCV_MCU_MCAUSE_INTERRUPT) != 0u) {
    eriscv_mcu_u32 code = mcause & ERISCV_MCU_MCAUSE_CODE_MASK;
    if (code == ERISCV_MCU_MCAUSE_MTI) {
      eriscv_mcu_timer_irq_handler();
      return mepc;
    }
    if (code == ERISCV_MCU_MCAUSE_MEI) {
      eriscv_mcu_machine_external_irq_handler();
      return mepc;
    }
  }
  if (mcause == 11u) {
    trap_stop = read_mcycle();
    trap_done = 1u;
    return mepc + 4u;
  }
  for (;;) {
  }
}

static eriscv_mcu_u32 measure(void (*operation)(void), volatile eriscv_mcu_u32 *instructions) {
  eriscv_mcu_u32 start_cycle = read_mcycle();
  eriscv_mcu_u32 start_instruction = read_minstret();
  operation();
  *instructions = read_minstret() - start_instruction;
  return read_mcycle() - start_cycle;
}

static eriscv_mcu_u32 measure_ecall(void) {
  eriscv_mcu_u32 start;
  trap_done = 0u;
  start = read_mcycle();
  __asm__ volatile ("ecall");
  while (trap_done == 0u) {
  }
  return trap_stop - start;
}

static eriscv_mcu_u32 measure_clint_wake(void) {
  eriscv_mcu_u64 now;
  eriscv_mcu_u32 start;
  timer_done = 0u;
  now = eriscv_mcu_clint_read_mtime();
  start = read_mcycle();
  eriscv_mcu_clint_set_mtimecmp(now + 128u);
  while (timer_done == 0u) {
    __asm__ volatile ("wfi");
  }
  return timer_stop - start;
}

static eriscv_mcu_u32 measure_plic_service(void) {
  eriscv_mcu_u32 start;
  plic_done = 0u;
  start = read_mcycle();
  eriscv_mcu_timer_start(128u, 1);
  while (plic_done == 0u) {
    __asm__ volatile ("wfi");
  }
  return plic_stop - start;
}

int main(void) {
  eriscv_microbench_report.done = 0u;
  eriscv_mcu_plic_set_priority(ERISCV_MCU_TIMER0_PLIC_SOURCE, 1u);
  eriscv_mcu_plic_set_enabled(ERISCV_MCU_TIMER0_PLIC_SOURCE, 1);
  eriscv_mcu_plic_set_threshold(0u);
  eriscv_mcu_enable_machine_irqs(ERISCV_MCU_MIE_MTIE | ERISCV_MCU_MIE_MEIE);

  eriscv_microbench_report.magic = REPORT_MAGIC;
  eriscv_microbench_report.iterations = ITERATIONS;
  eriscv_microbench_report.alu_cycles = measure(run_alu, &eriscv_microbench_report.alu_instructions);
  eriscv_microbench_report.branch_cycles = measure(run_branch, &eriscv_microbench_report.branch_instructions);
  eriscv_microbench_report.load_store_cycles = measure(run_load_store, &eriscv_microbench_report.load_store_instructions);
  eriscv_microbench_report.mul_cycles = measure(run_mul, &eriscv_microbench_report.mul_instructions);
  eriscv_microbench_report.div_cycles = measure(run_div, &eriscv_microbench_report.div_instructions);
  eriscv_microbench_report.fence_i_cycles = measure(run_fence_i, &eriscv_microbench_report.fence_i_instructions);
  eriscv_microbench_report.ecall_cycles = measure_ecall();
  eriscv_microbench_report.clint_wake_cycles = measure_clint_wake();
  eriscv_microbench_report.plic_service_cycles = measure_plic_service();
  eriscv_microbench_report.work_signature = work_buffer[0] ^ work_buffer[1] ^
                                             work_buffer[2] ^ work_buffer[3] ^
                                             work_buffer[4];
  eriscv_microbench_report.done = 1u;
  for (;;) {
  }
}
