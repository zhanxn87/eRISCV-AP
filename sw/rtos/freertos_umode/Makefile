# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

PYTHON ?= python3
CROSS_COMPILE ?= riscv64-unknown-elf-
CC := $(CROSS_COMPILE)gcc
EXTRA_CFLAGS ?=

SW_DIR ?= $(abspath ../..)
include $(SW_DIR)/isa.mk
THIRD_PARTY_DIR := $(abspath $(SW_DIR)/../../third_party)
BUILD_DIR ?= $(SW_DIR)/build/freertos_umode
KERNEL_DIR := $(THIRD_PARTY_DIR)/FreeRTOS-Kernel
PORT_DIR := $(KERNEL_DIR)/portable/GCC/RISC-V
PORT_EXT_DIR := $(PORT_DIR)/chip_specific_extensions/RISCV_MTIME_CLINT_no_extensions
ELF := $(BUILD_DIR)/freertos_umode.elf
IMEM_MEM := $(BUILD_DIR)/freertos_umode.imem.mem
DMEM_MEM := $(BUILD_DIR)/freertos_umode.dmem.mem

APP_SRCS := crt0.S port_start_mret.S port_trap_umode.S main.c pmp_context.c freertos_libc.c
KERNEL_SRCS := $(KERNEL_DIR)/tasks.c $(KERNEL_DIR)/queue.c $(KERNEL_DIR)/list.c
PORT_SRCS := $(PORT_DIR)/port.c $(PORT_DIR)/portASM.S
CFLAGS := -march=$(RTOS_ISA) -mabi=$(RTOS_ABI) -mcmodel=medany \
  -DERISCV_MCU_UART_DIVISOR=$(UART_DIVISOR)u \
  -ffreestanding -fno-builtin -fdata-sections -ffunction-sections \
  -Wall -Wextra -Werror -Os -I. -I$(SW_DIR)/include -I$(KERNEL_DIR)/include \
  -I$(PORT_DIR) -I$(PORT_EXT_DIR) $(EXTRA_CFLAGS)
LDFLAGS := -nostdlib -nostartfiles -Wl,--gc-sections \
  -Wl,--wrap=xPortStartFirstTask -Wl,--wrap=vTaskSwitchContext \
  -Wl,-Teriscv_mcu_umode.ld \
  -Wl,-Map,$(BUILD_DIR)/freertos_umode.map
LDLIBS := -lgcc

.PHONY: images clean

images: $(IMEM_MEM) $(DMEM_MEM)

$(ELF): $(APP_SRCS) $(KERNEL_SRCS) $(PORT_SRCS) FreeRTOSConfig.h eriscv_mcu_umode.ld | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) $(APP_SRCS) $(KERNEL_SRCS) $(PORT_SRCS) $(LDLIBS) -o $@

$(IMEM_MEM) $(DMEM_MEM): $(ELF) $(SW_DIR)/tools/elf_to_mem.py
	$(PYTHON) $(SW_DIR)/tools/elf_to_mem.py $(ELF) --imem-out $(IMEM_MEM) --dmem-out $(DMEM_MEM)

$(BUILD_DIR):
	mkdir -p $@

clean:
	rm -rf $(BUILD_DIR)
