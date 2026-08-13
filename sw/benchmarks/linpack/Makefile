# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

PYTHON ?= python3
CROSS_COMPILE ?= riscv64-unknown-elf-
CC := $(CROSS_COMPILE)gcc

SW_DIR ?= $(abspath ../..)
include $(SW_DIR)/isa.mk

# N=100 is the classic LINPACK matrix order. N=32 is the practical
# cycle-accurate simulation default; N=100 is intended for FPGA measurement.
ORDER ?= 32
REPETITIONS ?= 10
# Performance convention: published benchmark images use four-byte code layout.
PERF_LAYOUT_ALIGN_CFLAGS ?= -falign-functions=4 -falign-loops=4 -falign-jumps=4
BUILD_DIR ?= $(SW_DIR)/build/linpack/n$(ORDER)-r$(REPETITIONS)
ELF := $(BUILD_DIR)/linpack_sp.elf
IMEM_MEM := $(BUILD_DIR)/linpack_sp.imem.mem
DMEM_MEM := $(BUILD_DIR)/linpack_sp.dmem.mem

COMMON_SRCS := $(SW_DIR)/lib/crt0.S $(SW_DIR)/lib/trap.S $(SW_DIR)/lib/trap.c \
  $(SW_DIR)/lib/uart.c $(SW_DIR)/lib/dma.c
CFLAGS := -march=$(ISA) -mabi=$(ABI) -mcmodel=medany \
  -DERISCV_MCU_UART_DIVISOR=$(UART_DIVISOR)u \
  -ffreestanding -fno-builtin -fdata-sections -ffunction-sections \
  -Wall -Wextra -Werror -O2 -ffp-contract=off $(PERF_LAYOUT_ALIGN_CFLAGS) \
  -DLINPACK_ORDER=$(ORDER) -DLINPACK_REPETITIONS=$(REPETITIONS) -I$(SW_DIR)/include
LDFLAGS := -nostdlib -nostartfiles -Wl,--gc-sections \
  -Wl,-T$(SW_DIR)/linker/eriscv_mcu.ld -Wl,-Map,$(BUILD_DIR)/linpack_sp.map

.PHONY: images clean print-config

images: $(IMEM_MEM) $(DMEM_MEM)

$(ELF): $(COMMON_SRCS) main.c $(SW_DIR)/linker/eriscv_mcu.ld | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) $(COMMON_SRCS) main.c -o $@

$(IMEM_MEM) $(DMEM_MEM): $(ELF) $(SW_DIR)/tools/elf_to_mem.py
	$(PYTHON) $(SW_DIR)/tools/elf_to_mem.py $(ELF) --imem-out $(IMEM_MEM) --dmem-out $(DMEM_MEM)

$(BUILD_DIR):
	mkdir -p $@

print-config:
	@echo "ISA=$(ISA)"
	@echo "ABI=$(ABI)"
	@echo "SOC_CLOCK_HZ=$(SOC_CLOCK_HZ)"
	@echo "UART_MODE=$(UART_MODE)"
	@echo "UART_DIVISOR=$(UART_DIVISOR)"
	@echo "ORDER=$(ORDER)"
	@echo "REPETITIONS=$(REPETITIONS)"
	@echo "PERF_LAYOUT_ALIGN_CFLAGS=$(PERF_LAYOUT_ALIGN_CFLAGS)"
	@echo "BUILD_DIR=$(BUILD_DIR)"

clean:
	rm -rf $(SW_DIR)/build/linpack
