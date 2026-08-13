/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "FreeRTOS.h"
#include "queue.h"
#include "semphr.h"
#include "task.h"

#include "eriscv_mcu.h"
#include "drivers.h"

#define DEMO_EVENT 0x4652544fu
#define FREERTOS_TIMING_MAGIC 0x46525432u
#define TASK_DONE_CONSUMER 0x1u
#define TASK_DONE_TRIGGER  0x2u
#define TASK_DONE_YIELD_A  0x4u
#define TASK_DONE_YIELD_B  0x8u
#define TASK_DONE_ALL (TASK_DONE_CONSUMER | TASK_DONE_TRIGGER | TASK_DONE_YIELD_A | TASK_DONE_YIELD_B)

static StaticTask_t consumer_tcb;
static StackType_t consumer_stack[configMINIMAL_STACK_SIZE];
static StaticTask_t trigger_tcb;
static StackType_t trigger_stack[configMINIMAL_STACK_SIZE];
static StaticTask_t yield_a_tcb;
static StackType_t yield_a_stack[configMINIMAL_STACK_SIZE];
static StaticTask_t yield_b_tcb;
static StackType_t yield_b_stack[configMINIMAL_STACK_SIZE];
static StaticTask_t idle_tcb;
static StackType_t idle_stack[configMINIMAL_STACK_SIZE];
static StaticQueue_t event_queue_buffer;
static eriscv_mcu_u32 event_queue_storage[1];
static QueueHandle_t event_queue;
static StaticSemaphore_t event_mutex_buffer;
static SemaphoreHandle_t event_mutex;
static TaskHandle_t consumer_task;
static volatile eriscv_mcu_u32 timeslice_armed;
static volatile eriscv_mcu_u32 task_done_bits;
static volatile eriscv_mcu_u32 spi_async_done;
static volatile eriscv_mcu_u32 spi_async_result;
static volatile eriscv_mcu_u8 spi_async_rx;

volatile eriscv_mcu_u32 eriscv_freertos_result;
volatile eriscv_mcu_u32 eriscv_freertos_malloc_ok;

typedef struct {
  eriscv_mcu_u32 magic;
  eriscv_mcu_u32 yield_a_before_mcycle;
  eriscv_mcu_u32 yield_b_entry_mcycle;
  eriscv_mcu_u32 yield_b_before_mcycle;
  eriscv_mcu_u32 yield_a_resume_mcycle;
  eriscv_mcu_u32 timeslice_tick_mcycle;
  eriscv_mcu_u32 timeslice_b_entry_mcycle;
  eriscv_mcu_u32 timer_arm_mcycle;
  eriscv_mcu_u32 plic_isr_entry_mcycle;
  eriscv_mcu_u32 consumer_wake_mcycle;
} eriscv_freertos_timing_report_t;

volatile eriscv_freertos_timing_report_t eriscv_freertos_timing_report;

static eriscv_mcu_u32 read_mcycle(void) {
  eriscv_mcu_u32 value;

  __asm__ volatile ("csrr %0, mcycle" : "=r"(value));
  return value;
}

static void stop_apb_timer(void) {
  freertos_timer_stop();
}

static void mark_task_done(eriscv_mcu_u32 task_bit) {
  task_done_bits |= task_bit;
}

void vAssertCalled(const char *file, unsigned long line) {
  (void)file;
  (void)line;
  eriscv_freertos_result = 0xdead0001u;
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

void vApplicationTickHook(void) {
  if ((timeslice_armed != 0u) &&
      (eriscv_freertos_timing_report.timeslice_tick_mcycle == 0u)) {
    eriscv_freertos_timing_report.timeslice_tick_mcycle = read_mcycle();
    timeslice_armed = 0u;
  }
}

void freertos_risc_v_application_exception_handler(void) {
  vAssertCalled(__FILE__, __LINE__);
}

void freertos_risc_v_application_interrupt_handler(void) {
  eriscv_mcu_u32 mcause;
  eriscv_mcu_u32 source;
  eriscv_mcu_u32 event = DEMO_EVENT;
  BaseType_t higher_priority_task_woken = pdFALSE;

  eriscv_freertos_timing_report.plic_isr_entry_mcycle = read_mcycle();
  __asm__ volatile ("csrr %0, mcause" : "=r"(mcause));
  if ((mcause & ERISCV_MCU_MCAUSE_CODE_MASK) != ERISCV_MCU_MCAUSE_MEI) {
    vAssertCalled(__FILE__, __LINE__);
  }

  source = freertos_plic_claim();
  if (source == ERISCV_MCU_TIMER0_PLIC_SOURCE) {
    stop_apb_timer();
    if (xQueueSendFromISR(event_queue, &event, &higher_priority_task_woken) != pdPASS) {
      vAssertCalled(__FILE__, __LINE__);
    }
    vTaskNotifyGiveFromISR(consumer_task, &higher_priority_task_woken);
  } else if (source == ERISCV_MCU_SPI0_PLIC_SOURCE) {
    freertos_spi_irq_handler();
  } else {
    vAssertCalled(__FILE__, __LINE__);
  }
  freertos_plic_complete(source);
  portYIELD_FROM_ISR(higher_priority_task_woken);
}

static void spi_async_callback(int result, void *context) {
  (void)context;
  spi_async_result = (eriscv_mcu_u32)result;
  spi_async_done = 1u;
}

static void consumer_task_entry(void *argument) {
  eriscv_mcu_u32 event = 0u;

  (void)argument;
  configASSERT(xQueueReceive(event_queue, &event, pdMS_TO_TICKS(1u)) ==
               errQUEUE_EMPTY);
  configASSERT(ulTaskNotifyTake(pdTRUE, portMAX_DELAY) == 1u);
  eriscv_freertos_timing_report.consumer_wake_mcycle = read_mcycle();
  configASSERT(xQueueReceive(event_queue, &event, 0u) == pdPASS);
  configASSERT(event == DEMO_EVENT);
  configASSERT(xSemaphoreTake(event_mutex, 0u) == pdPASS);
  configASSERT(xSemaphoreGive(event_mutex) == pdPASS);
  configASSERT(eriscv_freertos_malloc_ok == 1u);
  mark_task_done(TASK_DONE_CONSUMER);
  while (task_done_bits != TASK_DONE_ALL) {
    vTaskDelay(pdMS_TO_TICKS(1u));
  }
  eriscv_mcu_uart_puts("FreeRTOS M-mode PASS\n");
  eriscv_freertos_result = 1u;
  vTaskDelete(0);
}

static void trigger_task_entry(void *argument) {
  static const eriscv_mcu_u8 spi_tx[2] = {0xa5u, 0xa5u};
  eriscv_mcu_u8 spi_rx[2] = {0u, 0u};
  eriscv_mcu_u32 wait_cycles;

  (void)argument;
  vTaskDelay(pdMS_TO_TICKS(1u));
  configASSERT(xSemaphoreTake(event_mutex, 0u) == pdPASS);
  configASSERT(xSemaphoreGive(event_mutex) == pdPASS);
  configASSERT(freertos_spi_init(2u, 0u) == 0);
  configASSERT(freertos_spi_transfer_buf(0u, spi_tx, spi_rx, 2u, 10000u) == 0);
  configASSERT(spi_rx[0] == 0x3cu && spi_rx[1] == 0x3cu);
  spi_async_done = 0u;
  spi_async_result = 0xffffffffu;
  spi_async_rx = 0u;
  configASSERT(freertos_spi_start_async(0u, spi_tx, (eriscv_mcu_u8 *)&spi_async_rx,
                                         1u, spi_async_callback, (void *)0) == 0);
  for (wait_cycles = 100000u;
       wait_cycles != 0u && spi_async_done == 0u;
       --wait_cycles) {
  }
  configASSERT(spi_async_done != 0u);
  configASSERT(spi_async_result == 0u);
  configASSERT(spi_async_rx == 0x3cu);
  eriscv_freertos_timing_report.timer_arm_mcycle = read_mcycle();
  freertos_timer_start(256u, 1);
  mark_task_done(TASK_DONE_TRIGGER);
  vTaskDelete(0);
}

static void yield_a_task_entry(void *argument) {
  (void)argument;
  eriscv_freertos_timing_report.yield_a_before_mcycle = read_mcycle();
  taskYIELD();
  eriscv_freertos_timing_report.yield_a_resume_mcycle = read_mcycle();

#ifdef FREERTOS_FORCE_STACK_OVERFLOW
  yield_a_stack[0] = 0u;
#endif
  timeslice_armed = 1u;
  while (timeslice_armed != 0u) {
  }
  vTaskDelay(pdMS_TO_TICKS(1u));
  mark_task_done(TASK_DONE_YIELD_A);
  vTaskDelete(0);
}

static void yield_b_task_entry(void *argument) {
  (void)argument;
  eriscv_freertos_timing_report.yield_b_entry_mcycle = read_mcycle();
  eriscv_freertos_timing_report.yield_b_before_mcycle = read_mcycle();
  taskYIELD();
  eriscv_freertos_timing_report.timeslice_b_entry_mcycle = read_mcycle();
  vTaskDelay(pdMS_TO_TICKS(1u));
  mark_task_done(TASK_DONE_YIELD_B);
  vTaskDelete(0);
}

static void test_malloc(void) {
  void *p;

  eriscv_freertos_malloc_ok = 0u; /* proves we entered this path */

  p = pvPortMalloc(256);
  configASSERT(p != NULL);

  /* write pattern: all bits toggle per byte */
  for (eriscv_mcu_u32 i = 0; i < 256; i++) {
    ((volatile eriscv_mcu_u8 *)p)[i] = (eriscv_mcu_u8)(i ^ 0xAAu);
  }
  /* verify pattern */
  for (eriscv_mcu_u32 i = 0; i < 256; i++) {
    if (((volatile eriscv_mcu_u8 *)p)[i] != (eriscv_mcu_u8)(i ^ 0xAAu)) {
      vAssertCalled(__FILE__, __LINE__);
    }
  }

  vPortFree(p);
  eriscv_freertos_malloc_ok = 1u;
}

int main(void) {
  extern void freertos_risc_v_trap_handler(void);

  test_malloc();

	eriscv_mcu_uart_init(ERISCV_MCU_UART_DIVISOR);
  __asm__ volatile ("csrw mtvec, %0" :: "r"(freertos_risc_v_trap_handler));
#ifdef FREERTOS_FORCE_ASSERT
  vAssertCalled(__FILE__, __LINE__);
#endif
  eriscv_freertos_timing_report.magic = FREERTOS_TIMING_MAGIC;
  eriscv_freertos_timing_report.yield_a_before_mcycle = 0u;
  eriscv_freertos_timing_report.yield_b_entry_mcycle = 0u;
  eriscv_freertos_timing_report.yield_b_before_mcycle = 0u;
  eriscv_freertos_timing_report.yield_a_resume_mcycle = 0u;
  eriscv_freertos_timing_report.timeslice_tick_mcycle = 0u;
  eriscv_freertos_timing_report.timeslice_b_entry_mcycle = 0u;
  eriscv_freertos_timing_report.timer_arm_mcycle = 0u;
  eriscv_freertos_timing_report.plic_isr_entry_mcycle = 0u;
  eriscv_freertos_timing_report.consumer_wake_mcycle = 0u;
  timeslice_armed = 0u;
  task_done_bits = 0u;
  spi_async_done = 0u;
  spi_async_result = 0xffffffffu;
  spi_async_rx = 0u;

  event_queue = xQueueCreateStatic(1u, sizeof(event_queue_storage[0]),
                                   (unsigned char *)event_queue_storage,
                                   &event_queue_buffer);
  configASSERT(event_queue != 0);
  event_mutex = xSemaphoreCreateMutexStatic(&event_mutex_buffer);
  configASSERT(event_mutex != 0);
  consumer_task = xTaskCreateStatic(consumer_task_entry, "consumer",
                                    configMINIMAL_STACK_SIZE, 0, 2u,
                                    consumer_stack, &consumer_tcb);
  configASSERT(consumer_task != 0);
  configASSERT(xTaskCreateStatic(yield_a_task_entry, "yield-a",
                                 configMINIMAL_STACK_SIZE, 0, 1u,
                                 yield_a_stack, &yield_a_tcb) != 0);
  configASSERT(xTaskCreateStatic(yield_b_task_entry, "yield-b",
                                 configMINIMAL_STACK_SIZE, 0, 1u,
                                 yield_b_stack, &yield_b_tcb) != 0);
  configASSERT(xTaskCreateStatic(trigger_task_entry, "trigger",
                                 configMINIMAL_STACK_SIZE, 0, 0u,
                                 trigger_stack, &trigger_tcb) != 0);

  freertos_plic_init_source(ERISCV_MCU_TIMER0_PLIC_SOURCE, 1u);
  vTaskStartScheduler();
  vAssertCalled(__FILE__, __LINE__);
  return 1;
}
