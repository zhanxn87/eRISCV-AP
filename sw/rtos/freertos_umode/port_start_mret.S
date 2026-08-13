/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "portContext.h"

.section .text.freertos_risc_v_start_first_umode, "ax"
.balign 4
.globl __wrap_xPortStartFirstTask
.type __wrap_xPortStartFirstTask, @function
.extern eriscv_umode_pmp_load_current
__wrap_xPortStartFirstTask:
  /* pxCurrentTCB is selected by FreeRTOS immediately before this handoff. */
  call eriscv_umode_pmp_load_current
  portcontextRESTORE_CONTEXT
