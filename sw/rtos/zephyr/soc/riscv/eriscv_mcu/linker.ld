/*
 * eRISCV-MCU Zephyr linker script
 *
 * Maps Zephyr's ROMABLE_REGION (FLASH) → IMEM and
 * RAMABLE_REGION (SRAM) → DMEM.
 *
 * Copyright (c) 2024 eRISCV-MCU Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

/* Include Zephyr's standard RISC-V linker template */
#include <zephyr/arch/riscv/common/linker.ld>
