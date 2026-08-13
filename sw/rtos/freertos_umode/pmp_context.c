/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "pmp_context.h"

#define PMP_A_NAPOT 0x18u
#define PMP_R       0x01u
#define PMP_W       0x02u
#define PMP_X       0x04u
#define USER_DMEM_SIZE 0x1000u
#define ERISCV_UMODE_MAX_TASKS 4u

typedef struct {
  TaskHandle_t task;
  eriscv_mcu_u32 pmpaddr1;
} pmp_template_t;

static pmp_template_t templates[ERISCV_UMODE_MAX_TASKS];

static eriscv_mcu_u32 napot_4k(eriscv_mcu_u32 base) {
  return (base >> 2) | 0x1ffu;
}

void eriscv_umode_pmp_register(TaskHandle_t task, eriscv_mcu_u32 user_dmem_base) {
  if ((task == 0) || (user_dmem_base & (USER_DMEM_SIZE - 1u)))
    vAssertCalled(__FILE__, __LINE__);
  for (unsigned int index = 0; index < ERISCV_UMODE_MAX_TASKS; ++index) {
    if (templates[index].task == task)
      vAssertCalled(__FILE__, __LINE__);
  }
  for (unsigned int index = 0; index < ERISCV_UMODE_MAX_TASKS; ++index) {
    if (templates[index].task == 0) {
      templates[index].task = task;
      templates[index].pmpaddr1 = napot_4k(user_dmem_base);
      return;
    }
  }
  vAssertCalled(__FILE__, __LINE__);
}

void eriscv_umode_pmp_load(TaskHandle_t task) {
  for (unsigned int index = 0; index < ERISCV_UMODE_MAX_TASKS; ++index) {
    if (templates[index].task == task) {
      /* Entry 0: RX ITCM [0x10000000, 0x10010000). */
      __asm__ volatile ("csrw pmpaddr0, %0" :: "r"(0x04001fffu));
      /* Entry 1: selected task's RW 4 KiB DTCM region. */
      __asm__ volatile ("csrw pmpaddr1, %0" :: "r"(templates[index].pmpaddr1));
      __asm__ volatile ("csrw pmpcfg0, %0" :: "r"(
          (PMP_A_NAPOT | PMP_R | PMP_X) |
          ((PMP_A_NAPOT | PMP_R | PMP_W) << 8)));
      return;
    }
  }
  /* The idle task is M-mode; retain the prior unlocked PMP template. */
}

void eriscv_umode_pmp_load_current(void) {
  eriscv_umode_pmp_load(xTaskGetCurrentTaskHandle());
}

void __wrap_vTaskSwitchContext(void) {
  extern void __real_vTaskSwitchContext(void);

  __real_vTaskSwitchContext();
  eriscv_umode_pmp_load(xTaskGetCurrentTaskHandle());
}
