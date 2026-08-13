/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

#include "eriscv_mcu.h"

#define configUSE_PREEMPTION                    1
#define configUSE_TIME_SLICING                   1
#define configUSE_PORT_OPTIMISED_TASK_SELECTION  1
#define configUSE_TICKLESS_IDLE                  0
#define configUSE_IDLE_HOOK                       0
#define configUSE_TICK_HOOK                       1
#define configCPU_CLOCK_HZ                       ERISCV_MCU_SOC_CLOCK_HZ
#define configTICK_RATE_HZ                       1000U
#define configMAX_PRIORITIES                     3
#define configMINIMAL_STACK_SIZE                 128U
#define configMAX_TASK_NAME_LEN                  16U
#define configUSE_16_BIT_TICKS                   0
#define configIDLE_SHOULD_YIELD                  1

#define configSUPPORT_STATIC_ALLOCATION          1
#define configSUPPORT_DYNAMIC_ALLOCATION         1
#define configTOTAL_HEAP_SIZE                    (8 * 1024)
#define configUSE_TASK_NOTIFICATIONS             1
#define configUSE_MUTEXES                        1
#define configUSE_RECURSIVE_MUTEXES              0
#define configUSE_COUNTING_SEMAPHORES            0
#define configUSE_QUEUE_SETS                     0
#define configUSE_TIMERS                         0
#define configUSE_CO_ROUTINES                    0

#define configCHECK_FOR_STACK_OVERFLOW           2
#define configISR_STACK_SIZE_WORDS               256U
#define configMTIME_BASE_ADDRESS                 (ERISCV_MCU_CLINT_BASE + ERISCV_MCU_CLINT_MTIME)
#define configMTIMECMP_BASE_ADDRESS              (ERISCV_MCU_CLINT_BASE + ERISCV_MCU_CLINT_MTIMECMP)

#define INCLUDE_vTaskDelay                       1
#define INCLUDE_vTaskDelete                      1
#define INCLUDE_vTaskSuspend                     0
#define INCLUDE_xTaskAbortDelay                  0
#define INCLUDE_xTaskGetCurrentTaskHandle        1

void vAssertCalled(const char *file, unsigned long line);
#define configASSERT(expression) ((expression) ? (void)0 : vAssertCalled(__FILE__, __LINE__))

#endif
