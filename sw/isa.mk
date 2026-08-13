# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

# eRISCV-M2 software build contract.
#
# The pinned GCC accepts Zcf in -march, so generated software artifacts
# explicitly declare it alongside the RV32F and RV32C base extensions.
ISA ?= rv32imfc_zicsr_zifencei_zicntr_zihpm_zihintpause_zba_zbb_zbs_zicond_zcf
ABI ?= ilp32f
# RTOS task context does not save FPR/FCSR yet. Keep RTOS objects in the
# supported integer execution subset until that context support is added.
RTOS_ABI ?= ilp32
RTOS_ISA ?= rv32imc_zicsr_zifencei_zicntr_zihpm_zihintpause_zba_zbb_zbs_zicond

ERISCV_GCC_VERSION := 15.3.0
ifeq ($(strip $(MAKECMDGOALS)),)
ERISCV_GCC_CHECK := 1
else ifneq ($(filter-out clean,$(MAKECMDGOALS)),)
ERISCV_GCC_CHECK := 1
endif
ifneq ($(ERISCV_GCC_CHECK),)
ERISCV_GCC_VERSION_ACTUAL := $(shell $(CROSS_COMPILE)gcc -dumpfullversion -dumpversion 2>/dev/null)
ifneq ($(ERISCV_GCC_VERSION_ACTUAL),$(ERISCV_GCC_VERSION))
$(error eRISCV requires $(CROSS_COMPILE)gcc $(ERISCV_GCC_VERSION); run tools/toolchain/bootstrap_riscv_gcc15.sh and prepend its bin directory to PATH)
endif
endif

# Hardware timing values match rtl/soc/soc_pkg.sv. UART_MODE selects the
# runtime-UART image profile; UART_DIVISOR remains an expert override.
SOC_CLOCK_HZ ?= 100000000
UART_BOARD_DIVISOR ?= 868
UART_MODE ?= sim

ifeq ($(UART_MODE),sim)
UART_DIVISOR ?= 8
else ifeq ($(UART_MODE),board)
UART_DIVISOR ?= $(UART_BOARD_DIVISOR)
else
$(error UART_MODE must be sim or board)
endif
