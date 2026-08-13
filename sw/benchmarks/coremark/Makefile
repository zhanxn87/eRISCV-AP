# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

PYTHON ?= python3
CROSS_COMPILE ?= riscv64-unknown-elf-
CC := $(CROSS_COMPILE)gcc

SW_DIR ?= $(abspath ../..)
include $(SW_DIR)/isa.mk
THIRD_PARTY_DIR := $(abspath $(SW_DIR)/../../third_party)
BUILD_DIR ?= $(SW_DIR)/build/coremark
COREMARK_DIR := $(THIRD_PARTY_DIR)/CoreMark
ITERATIONS ?= 10
COREMARK_CLOCK_HZ ?= $(SOC_CLOCK_HZ)
COREMARK_OPTFLAGS ?= -O2
# Performance convention: published benchmark images use four-byte code layout.
# Set PERF_LAYOUT_ALIGN_CFLAGS= only for archived-layout reproduction.
PERF_LAYOUT_ALIGN_CFLAGS ?= -falign-functions=4 -falign-loops=4 -falign-jumps=4
COREMARK_COMPILER_FLAGS := $(COREMARK_OPTFLAGS) $(PERF_LAYOUT_ALIGN_CFLAGS) -march=$(ISA) -mabi=$(ABI) -mcmodel=medany -ffreestanding -fno-builtin -fdata-sections -ffunction-sections
ELF := $(BUILD_DIR)/coremark.elf
IMEM_MEM := $(BUILD_DIR)/coremark.imem.mem
DMEM_MEM := $(BUILD_DIR)/coremark.dmem.mem

BSP_SRCS := $(SW_DIR)/lib/crt0.S $(SW_DIR)/lib/trap.S $(SW_DIR)/lib/trap.c \
  $(SW_DIR)/lib/uart.c $(SW_DIR)/lib/dma.c
COREMARK_SRCS := $(COREMARK_DIR)/core_list_join.c $(COREMARK_DIR)/core_main.c \
  $(COREMARK_DIR)/core_matrix.c $(COREMARK_DIR)/core_state.c \
  $(COREMARK_DIR)/core_util.c core_portme.c
CFLAGS := -march=$(ISA) -mabi=$(ABI) -mcmodel=medany \
  -DERISCV_MCU_UART_DIVISOR=$(UART_DIVISOR)u \
  -ffreestanding -fno-builtin -fdata-sections -ffunction-sections \
  $(COREMARK_OPTFLAGS) $(PERF_LAYOUT_ALIGN_CFLAGS) -I$(SW_DIR)/include -I. -I$(COREMARK_DIR) \
  -DITERATIONS=$(ITERATIONS) -DTOTAL_DATA_SIZE=2000 -DVALIDATION_RUN=1 \
  '-DERISCV_COREMARK_COMPILER_FLAGS="$(COREMARK_COMPILER_FLAGS)"' \
  -DCOREMARK_CLOCK_HZ=$(COREMARK_CLOCK_HZ)u
LDFLAGS := -nostdlib -nostartfiles -Wl,--gc-sections \
  -Wl,-T$(SW_DIR)/linker/eriscv_mcu.ld -Wl,-Map,$(BUILD_DIR)/coremark.map

.PHONY: images clean print-config

images: $(IMEM_MEM) $(DMEM_MEM)

$(ELF): $(BSP_SRCS) $(COREMARK_SRCS) core_portme.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) $(BSP_SRCS) $(COREMARK_SRCS) -o $@

$(IMEM_MEM) $(DMEM_MEM): $(ELF) $(SW_DIR)/tools/elf_to_mem.py
	$(PYTHON) $(SW_DIR)/tools/elf_to_mem.py $(ELF) --imem-out $(IMEM_MEM) --dmem-out $(DMEM_MEM)

$(BUILD_DIR):
	mkdir -p $@

print-config:
	@echo "ITERATIONS=$(ITERATIONS)"
	@echo "ISA=$(ISA)"
	@echo "ABI=$(ABI)"
	@echo "COREMARK_OPTFLAGS=$(COREMARK_OPTFLAGS)"
	@echo "PERF_LAYOUT_ALIGN_CFLAGS=$(PERF_LAYOUT_ALIGN_CFLAGS)"
	@echo "COREMARK_COMPILER_FLAGS=$(COREMARK_COMPILER_FLAGS)"
	@echo "COREMARK_CLOCK_HZ=$(COREMARK_CLOCK_HZ)"
	@echo "ELF=$(ELF)"
	@echo "IMEM=$(IMEM_MEM)"
	@echo "DMEM=$(DMEM_MEM)"

clean:
	rm -rf $(BUILD_DIR)
