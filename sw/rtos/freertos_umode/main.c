/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "FreeRTOS.h"
#include "task.h"

#include "eriscv_mcu.h"
#include "pmp_context.h"

#define MSTATUS_MPP_MASK (3u << 11)
#define MCAUSE_ECALL_FROM_UMODE 8u
#define MCAUSE_STORE_ACCESS_FAULT 7u
#define USER0_DMEM_BASE 0x11000000u
#define USER1_DMEM_BASE 0x11001000u
#define USER2_DMEM_BASE 0x11002000u
#define USER3_DMEM_BASE 0x11003000u
#define USER_PROGRESS_STARTED 0x53544152u
#define USER_PROGRESS_RESUMED 0x52455355u
#define USER_NOTIFY_CHAIN_MASK ((1u << 1) | (1u << 2) | (1u << 3))
#define UMODE_SYSCALL_YIELD 1u
#define UMODE_SYSCALL_EXIT 2u
#define UMODE_SYSCALL_DELAY 3u
#define UMODE_SYSCALL_NOTIFY_GIVE 4u
#define UMODE_SYSCALL_NOTIFY_WAIT 5u
#define UMODE_SYSCALL_RECORD_MCYCLE 6u

#define UMODE_TIMING_MAGIC 0x554d5431u

#define TIMING_YIELD_A_BEFORE  0u
#define TIMING_YIELD_B_ENTRY   1u
#define TIMING_YIELD_B_BEFORE  2u
#define TIMING_YIELD_A_RESUME  3u
#define TIMING_DELAY_BEFORE    4u
#define TIMING_DELAY_AFTER     5u
#define TIMING_NOTIFY_BEFORE   6u
#define TIMING_NOTIFY_AFTER    7u
#define TIMING_WAIT_BEFORE     8u
#define TIMING_WAIT_AFTER      9u

static StaticTask_t user0_tcb;
static StackType_t user0_stack[configMINIMAL_STACK_SIZE]
    __attribute__((section(".user0_bss"), aligned(16)));
static volatile eriscv_mcu_u32 user0_progress
    __attribute__((section(".user0_bss")));
static StaticTask_t user1_tcb;
static StackType_t user1_stack[configMINIMAL_STACK_SIZE]
    __attribute__((section(".user1_bss"), aligned(16)));
static volatile eriscv_mcu_u32 user1_progress
    __attribute__((section(".user1_bss")));
static StaticTask_t idle_tcb;
static StackType_t idle_stack[configMINIMAL_STACK_SIZE];
static volatile eriscv_mcu_u32 kernel_secret;
static volatile eriscv_mcu_u32 user0_kernel_fault_seen;
static volatile eriscv_mcu_u32 user1_peer_fault_seen;
static volatile eriscv_mcu_u32 user1_complete;
static TaskHandle_t user1_task_handle;
static StaticTask_t user2_tcb;
static StackType_t user2_stack[configMINIMAL_STACK_SIZE]
    __attribute__((section(".user2_bss"), aligned(16)));
static volatile eriscv_mcu_u32 user2_progress
    __attribute__((section(".user2_bss")));
static TaskHandle_t user2_task_handle;
static StaticTask_t user3_tcb;
static StackType_t user3_stack[configMINIMAL_STACK_SIZE]
    __attribute__((section(".user3_bss"), aligned(16)));
static volatile eriscv_mcu_u32 user3_progress
    __attribute__((section(".user3_bss")));
static TaskHandle_t user3_task_handle;
static volatile eriscv_mcu_u32 user0_complete;
static volatile eriscv_mcu_u32 user2_complete;
static volatile eriscv_mcu_u32 umode_notify_given_mask;
static volatile eriscv_mcu_u32 umode_notify_woken_mask;
static TaskHandle_t user0_task_handle;
static TaskHandle_t umode_task_table[4];

typedef struct {
  eriscv_mcu_u32 magic;
  eriscv_mcu_u32 yield_a_before;
  eriscv_mcu_u32 yield_b_entry;
  eriscv_mcu_u32 yield_b_before;
  eriscv_mcu_u32 yield_a_resume;
  eriscv_mcu_u32 delay_before;
  eriscv_mcu_u32 delay_after;
  eriscv_mcu_u32 notify_before;
  eriscv_mcu_u32 notify_after;
  eriscv_mcu_u32 wait_before;
  eriscv_mcu_u32 wait_after;
} eriscv_umode_timing_report_t;

volatile eriscv_umode_timing_report_t eriscv_umode_timing_report;
volatile eriscv_mcu_u32 eriscv_freertos_umode_result;

void vAssertCalled(const char *file, unsigned long line) {
  (void)file;
  (void)line;
  eriscv_freertos_umode_result = 0xdead0001u;
  for (;;) {
  }
}

void vApplicationStackOverflowHook(TaskHandle_t task, char *task_name) {
  (void)task;
  (void)task_name;
  vAssertCalled(__FILE__, __LINE__);
}

void vApplicationGetIdleTaskMemory(StaticTask_t **tcb, StackType_t **stack,
                                   configSTACK_DEPTH_TYPE *stack_size) {
  *tcb = &idle_tcb;
  *stack = idle_stack;
  *stack_size = configMINIMAL_STACK_SIZE;
}

void freertos_risc_v_application_interrupt_handler(void) {
  vAssertCalled(__FILE__, __LINE__);
}

void freertos_risc_v_application_exception_handler(void) {
  eriscv_mcu_u32 mcause;
  eriscv_mcu_u32 mtval;
  eriscv_mcu_u32 service;

  __asm__ volatile ("csrr %0, mcause" : "=r"(mcause));
  __asm__ volatile ("csrr %0, mtval" : "=r"(mtval));
#if 0  /* PMP fault tests — restored in Step 3 */
  if ((mcause == MCAUSE_STORE_ACCESS_FAULT) &&
      (mtval == (eriscv_mcu_u32)&kernel_secret) &&
      (user0_progress == USER_PROGRESS_STARTED)) {
    user0_kernel_fault_seen = 1u;
    return;
  }
  if ((mcause == MCAUSE_STORE_ACCESS_FAULT) &&
      (mtval == (eriscv_mcu_u32)&user0_progress) &&
      (user1_progress == USER_PROGRESS_STARTED)) {
    user1_peer_fault_seen = 1u;
    return;
  }
#endif
  if (mcause == MCAUSE_ECALL_FROM_UMODE) {
    __asm__ volatile ("mv %0, a7" : "=r"(service));
    if (service == UMODE_SYSCALL_DELAY) {
      eriscv_mcu_u32 ticks;
      __asm__ volatile ("mv %0, a0" : "=r"(ticks));
      vTaskDelay(ticks);
      return;
    }
    if (service == UMODE_SYSCALL_NOTIFY_GIVE) {
      eriscv_mcu_u32 task_id;
      __asm__ volatile ("mv %0, a0" : "=r"(task_id));
      if (task_id < 4u && umode_task_table[task_id] != 0) {
        xTaskNotifyGive(umode_task_table[task_id]);
        umode_notify_given_mask |= 1u << task_id;
      }
      return;
    }
    if (service == UMODE_SYSCALL_NOTIFY_WAIT) {
      TaskHandle_t task = xTaskGetCurrentTaskHandle();
      ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
      for (eriscv_mcu_u32 task_id = 1u; task_id < 4u; task_id++) {
        if (task == umode_task_table[task_id]) {
          umode_notify_woken_mask |= 1u << task_id;
          break;
        }
      }
      return;
    }
    if (service == UMODE_SYSCALL_RECORD_MCYCLE) {
      eriscv_mcu_u32 timing_id;
      eriscv_mcu_u32 val;
      __asm__ volatile ("mv %0, a0" : "=r"(timing_id));
      __asm__ volatile ("csrr %0, mcycle" : "=r"(val));
      switch (timing_id) {
        case TIMING_YIELD_A_BEFORE: eriscv_umode_timing_report.yield_a_before = val; break;
        case TIMING_YIELD_B_ENTRY:  eriscv_umode_timing_report.yield_b_entry  = val; break;
        case TIMING_YIELD_B_BEFORE: eriscv_umode_timing_report.yield_b_before = val; break;
        case TIMING_YIELD_A_RESUME: eriscv_umode_timing_report.yield_a_resume = val; break;
        case TIMING_DELAY_BEFORE:   eriscv_umode_timing_report.delay_before   = val; break;
        case TIMING_DELAY_AFTER:    eriscv_umode_timing_report.delay_after    = val; break;
        case TIMING_NOTIFY_BEFORE:  eriscv_umode_timing_report.notify_before  = val; break;
        case TIMING_NOTIFY_AFTER:   eriscv_umode_timing_report.notify_after   = val; break;
        case TIMING_WAIT_BEFORE:    eriscv_umode_timing_report.wait_before    = val; break;
        case TIMING_WAIT_AFTER:     eriscv_umode_timing_report.wait_after     = val; break;
        default: break;
      }
      return;
    }
    if (service == UMODE_SYSCALL_YIELD) {
      vTaskSwitchContext();
      return;
    }
    if ((service == UMODE_SYSCALL_EXIT) &&
        (xTaskGetCurrentTaskHandle() == user0_task_handle)) {
      user0_complete = 1u;
      vTaskDelete(0);
      return;
    }
    if ((service == UMODE_SYSCALL_EXIT) &&
        (xTaskGetCurrentTaskHandle() == user1_task_handle)) {
      user1_complete = 1u;
      vTaskDelete(0);
      return;
    }
    if ((service == UMODE_SYSCALL_EXIT) &&
        (xTaskGetCurrentTaskHandle() == user2_task_handle)) {
      user2_complete = 1u;
      vTaskDelete(0);
      return;
    }
    if ((service == UMODE_SYSCALL_EXIT) &&
        (xTaskGetCurrentTaskHandle() == user3_task_handle)) {
      if ((user0_complete == 1u) &&
          (user1_complete == 1u) &&
          (user2_complete == 1u) &&
          (user1_progress == USER_PROGRESS_RESUMED) &&
          (user2_progress == USER_PROGRESS_RESUMED) &&
          (user3_progress == USER_PROGRESS_RESUMED) &&
          (umode_notify_given_mask == USER_NOTIFY_CHAIN_MASK) &&
          (umode_notify_woken_mask == USER_NOTIFY_CHAIN_MASK) &&
          (eriscv_umode_timing_report.wait_after != 0u)) {
        eriscv_freertos_umode_result = 1u;
      } else {
        eriscv_freertos_umode_result = 0xdead0001u;
      }
      vTaskDelete(0);
      return;
    }
  }
  vAssertCalled(__FILE__, __LINE__);
}

static void user_syscall1(eriscv_mcu_u32 service, eriscv_mcu_u32 arg) {
  register eriscv_mcu_u32 a0 __asm__("a0") = arg;
  register eriscv_mcu_u32 a7 __asm__("a7") = service;
  __asm__ volatile ("ecall" :: "r"(a0), "r"(a7) : "memory");
}

static void user0_task_entry(void *argument) {
  (void)argument;
  user0_progress = USER_PROGRESS_STARTED;
#ifdef ERISCV_UMODE_BAD_SYSCALL_TEST
  /* Deliberately exercise the unknown-service fail-stop path. */
  user_syscall1(0x7fu, 0u);
#endif
  /* yield latency: record before yield, resume point after yield */
  user_syscall1(UMODE_SYSCALL_RECORD_MCYCLE, TIMING_YIELD_A_BEFORE);
  user_syscall1(UMODE_SYSCALL_YIELD, 0u);
  user_syscall1(UMODE_SYSCALL_RECORD_MCYCLE, TIMING_YIELD_A_RESUME);
  /* delay latency */
  user_syscall1(UMODE_SYSCALL_RECORD_MCYCLE, TIMING_DELAY_BEFORE);
  user_syscall1(UMODE_SYSCALL_DELAY, 3u);
  user_syscall1(UMODE_SYSCALL_RECORD_MCYCLE, TIMING_DELAY_AFTER);
  /* notify latency: before give */
  user_syscall1(UMODE_SYSCALL_RECORD_MCYCLE, TIMING_NOTIFY_BEFORE);
  user_syscall1(UMODE_SYSCALL_NOTIFY_GIVE, 1u);
  user_syscall1(UMODE_SYSCALL_RECORD_MCYCLE, TIMING_NOTIFY_AFTER);
  user_syscall1(UMODE_SYSCALL_EXIT, 0u);
  for (;;) {}
}

static void user1_task_entry(void *argument) {
  (void)argument;
  user1_progress = USER_PROGRESS_STARTED;
  /* yield_b side of voluntary yield measurement */
  user_syscall1(UMODE_SYSCALL_RECORD_MCYCLE, TIMING_YIELD_B_ENTRY);
  user_syscall1(UMODE_SYSCALL_RECORD_MCYCLE, TIMING_YIELD_B_BEFORE);
  user_syscall1(UMODE_SYSCALL_YIELD, 0u);
  /* notify wait latency */
  user_syscall1(UMODE_SYSCALL_RECORD_MCYCLE, TIMING_WAIT_BEFORE);
  user_syscall1(UMODE_SYSCALL_NOTIFY_WAIT, 0u);
  user1_progress = USER_PROGRESS_RESUMED;
  user_syscall1(UMODE_SYSCALL_RECORD_MCYCLE, TIMING_WAIT_AFTER);
  user_syscall1(UMODE_SYSCALL_NOTIFY_GIVE, 2u);
  user_syscall1(UMODE_SYSCALL_EXIT, 0u);
  for (;;) {}
}

static void user2_task_entry(void *argument) {
  (void)argument;
  user2_progress = USER_PROGRESS_STARTED;
  /* Block until notified by user1, then notify user3 and exit. */
  user_syscall1(UMODE_SYSCALL_NOTIFY_WAIT, 0u);
  user2_progress = USER_PROGRESS_RESUMED;
  user_syscall1(UMODE_SYSCALL_NOTIFY_GIVE, 3u);
  user_syscall1(UMODE_SYSCALL_EXIT, 0u);
  for (;;) {}
}

static void user3_task_entry(void *argument) {
  (void)argument;
  user3_progress = USER_PROGRESS_STARTED;
  /* Block until notified by user2, then exit. */
  user_syscall1(UMODE_SYSCALL_NOTIFY_WAIT, 0u);
  user3_progress = USER_PROGRESS_RESUMED;
  user_syscall1(UMODE_SYSCALL_EXIT, 0u);
  for (;;) {}
}

static void set_initial_task_to_umode(TaskHandle_t task) {
  volatile StackType_t *context = *(volatile StackType_t * volatile *)task;

  /* FreeRTOS documents pxTopOfStack as the first TCB member for port code. */
  context[1] &= ~MSTATUS_MPP_MASK;
}

int main(void) {
  extern void freertos_risc_v_trap_handler(void);
  extern void eriscv_umode_trap_handler(void);
  __asm__ volatile ("csrw mtvec, %0" :: "r"(eriscv_umode_trap_handler));
  kernel_secret = 0u;
  eriscv_freertos_umode_result = 0u;
  eriscv_umode_timing_report.magic = UMODE_TIMING_MAGIC;
  eriscv_umode_timing_report.yield_a_before = 0u;
  eriscv_umode_timing_report.yield_b_entry = 0u;
  eriscv_umode_timing_report.yield_b_before = 0u;
  eriscv_umode_timing_report.yield_a_resume = 0u;
  eriscv_umode_timing_report.delay_before = 0u;
  eriscv_umode_timing_report.delay_after = 0u;
  eriscv_umode_timing_report.notify_before = 0u;
  eriscv_umode_timing_report.notify_after = 0u;
  eriscv_umode_timing_report.wait_before = 0u;
  eriscv_umode_timing_report.wait_after = 0u;
  user0_complete = 0u;
  user1_complete = 0u;
  user2_complete = 0u;
  umode_notify_given_mask = 0u;
  umode_notify_woken_mask = 0u;
  user0_task_handle = xTaskCreateStatic(user0_task_entry, "user0", configMINIMAL_STACK_SIZE,
                                        0, 2u, user0_stack, &user0_tcb);
  configASSERT(user0_task_handle != 0);
  umode_task_table[0] = user0_task_handle;
  set_initial_task_to_umode(user0_task_handle);
  eriscv_umode_pmp_register(user0_task_handle, USER0_DMEM_BASE);
  eriscv_umode_pmp_load(user0_task_handle);
  user1_task_handle = xTaskCreateStatic(user1_task_entry, "user1", configMINIMAL_STACK_SIZE,
                                        0, 2u, user1_stack, &user1_tcb);
  configASSERT(user1_task_handle != 0);
  umode_task_table[1] = user1_task_handle;
  set_initial_task_to_umode(user1_task_handle);
  eriscv_umode_pmp_register(user1_task_handle, USER1_DMEM_BASE);
  eriscv_umode_pmp_load(user1_task_handle);
  user2_task_handle = xTaskCreateStatic(user2_task_entry, "user2", configMINIMAL_STACK_SIZE,
                                        0, 2u, user2_stack, &user2_tcb);
  configASSERT(user2_task_handle != 0);
  umode_task_table[2] = user2_task_handle;
  set_initial_task_to_umode(user2_task_handle);
  eriscv_umode_pmp_register(user2_task_handle, USER2_DMEM_BASE);
  eriscv_umode_pmp_load(user2_task_handle);
  user3_task_handle = xTaskCreateStatic(user3_task_entry, "user3", configMINIMAL_STACK_SIZE,
                                        0, 2u, user3_stack, &user3_tcb);
  configASSERT(user3_task_handle != 0);
  umode_task_table[3] = user3_task_handle;
  set_initial_task_to_umode(user3_task_handle);
  eriscv_umode_pmp_register(user3_task_handle, USER3_DMEM_BASE);
  eriscv_umode_pmp_load(user3_task_handle);
#ifdef ERISCV_UMODE_PMP_NEGATIVE_TEST
  eriscv_umode_pmp_register(user1_task_handle, USER1_DMEM_BASE);
#endif
  vTaskStartScheduler();
  vAssertCalled(__FILE__, __LINE__);
  return 1;
}
