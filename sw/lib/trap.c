/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "eriscv_mcu.h"

/* Default weak handler for timer interrupt — override in application if needed. */
__attribute__((weak)) void eriscv_mcu_timer_irq_handler(void) {
  /* no-op: clear MTIP by writing to MTIMECMP */
}

/* Default weak handler for software interrupt — override in application if needed. */
__attribute__((weak)) void eriscv_mcu_software_irq_handler(void) {
  eriscv_mcu_clint_set_msip(0);
}

void eriscv_mcu_machine_external_irq_handler(void) {
  eriscv_mcu_u32 source_id = eriscv_mcu_plic_claim();

  if (source_id == ERISCV_MCU_UART0_PLIC_SOURCE) {
    eriscv_mcu_uart_irq_handler();
  } else if (source_id == ERISCV_MCU_DMA_PLIC_SOURCE) {
    eriscv_mcu_dma_irq_handler();
  }
  if (source_id != 0u) {
    eriscv_mcu_plic_complete(source_id);
  }
}

__attribute__((weak)) eriscv_mcu_u32 eriscv_mcu_trap_handler(
    eriscv_mcu_u32 mcause, eriscv_mcu_u32 mepc, eriscv_mcu_u32 mtval) {
  (void)mtval;
  if ((mcause & ERISCV_MCU_MCAUSE_INTERRUPT) != 0u) {
    eriscv_mcu_u32 code = mcause & ERISCV_MCU_MCAUSE_CODE_MASK;
    if (code == ERISCV_MCU_MCAUSE_MEI) {
      eriscv_mcu_machine_external_irq_handler();
      return mepc;
    }
    if (code == ERISCV_MCU_MCAUSE_MTI) {
      eriscv_mcu_timer_irq_handler();
      return mepc;
    }
    if (code == ERISCV_MCU_MCAUSE_MSI) {
      eriscv_mcu_software_irq_handler();
      return mepc;
    }
  }
  for (;;) {
  }
}
