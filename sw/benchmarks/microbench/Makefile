# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

PYTHON ?= python3
CROSS_COMPILE ?= riscv64-unknown-elf-
CC := $(CROSS_COMPILE)gcc

SW_DIR ?= $(abspath ../..)
include $(SW_DIR)/isa.mk
BUILD_DIR ?= $(SW_DIR)/build/microbench
# Performance convention: published benchmark images use four-byte code layout.
PERF_LAYOUT_ALIGN_CFLAGS ?= -falign-functions=4 -falign-loops=4 -falign-jumps=4
ELF := $(BUILD_DIR)/microbench.elf
IMEM_MEM := $(BUILD_DIR)/microbench.imem.mem
DMEM_MEM := $(BUILD_DIR)/microbench.dmem.mem
SRCS := $(SW_DIR)/lib/crt0.S $(SW_DIR)/lib/trap.S main.c
CFLAGS := -march=$(ISA) -mabi=$(ABI) -mcmodel=medany \
  -DERISCV_MCU_UART_DIVISOR=$(UART_DIVISOR)u \
  -ffreestanding -fno-builtin -fdata-sections -ffunction-sections \
  -Wall -Wextra -Werror -O2 $(PERF_LAYOUT_ALIGN_CFLAGS) -I$(SW_DIR)/include
LDFLAGS := -nostdlib -nostartfiles -Wl,--gc-sections \
  -Wl,-T$(SW_DIR)/linker/eriscv_mcu.ld -Wl,-Map,$(BUILD_DIR)/microbench.map

.PHONY: images clean

images: $(IMEM_MEM) $(DMEM_MEM)

$(ELF): $(SRCS) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) $(SRCS) -o $@

$(IMEM_MEM) $(DMEM_MEM): $(ELF) $(SW_DIR)/tools/elf_to_mem.py
	$(PYTHON) $(SW_DIR)/tools/elf_to_mem.py $(ELF) --imem-out $(IMEM_MEM) --dmem-out $(DMEM_MEM)

$(BUILD_DIR):
	mkdir -p $@

clean:
	rm -rf $(BUILD_DIR)
