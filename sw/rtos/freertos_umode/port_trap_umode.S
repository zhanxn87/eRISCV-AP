/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "portContext.h"

.section .text.freertos_risc_v_umode_trap, "ax"
.balign 4
.globl eriscv_umode_trap_handler
.type eriscv_umode_trap_handler, @function
.extern freertos_risc_v_application_exception_handler
.extern freertos_risc_v_trap_handler

eriscv_umode_trap_handler:
  /* Preserve scratch registers before inspecting mcause. */
  addi sp, sp, -8
  sw t0, 0(sp)
  sw t1, 4(sp)
  csrr t0, mcause
  li t1, 8
  bne t0, t1, 1f
  lw t1, 4(sp)
  lw t0, 0(sp)
  addi sp, sp, 8

  /* Keep the U-mode task stack active while dispatching a blocking syscall.
   * A nested M-mode portYIELD then saves a resumable kernel continuation in
   * that task's TCB instead of on the shared ISR stack. */
  portcontextSAVE_CONTEXT_INTERNAL
  /* Stash the U-mode context pointer and the pre-call pxCurrentTCB.  After
   * the C handler returns the TCB may point to an inner M-mode frame (if the
   * task blocked and was later resumed) or to a different task (if the
   * handler yielded).  We override the TCB with the U-mode frame only when
   * the owning task is still current. */
  mv s0, sp
  load_x s1, pxCurrentTCB
  /* The saved frame retains the outer U-mode return state.  Mark the live
   * trap context M-mode before a blocking syscall can issue an inner ECALL,
   * so the stock FreeRTOS trap path resumes this C continuation in M-mode. */
  csrr t0, mstatus
  li t1, ~(3 << 11)
  and t0, t0, t1
  li t1, (3 << 11)
  or t0, t0, t1
  csrw mstatus, t0
  csrr a1, mepc
  addi a1, a1, 4
  store_x a1, 0(sp)
  call freertos_risc_v_application_exception_handler

  /* If the C handler yielded, pxCurrentTCB changed — let RESTORE_CONTEXT
   * load the new task normally.  Otherwise the owner is still current and
   * we must redirect the TCB to the U-mode frame we saved. */
  load_x t0, pxCurrentTCB
  bne s1, t0, 2f
  store_x s0, 0(t0)
2:
  portcontextRESTORE_CONTEXT

1:
  lw t1, 4(sp)
  lw t0, 0(sp)
  addi sp, sp, 8
  j freertos_risc_v_trap_handler
