# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

PYTHON ?= python3
CROSS_COMPILE ?= riscv64-unknown-elf-
CC := $(CROSS_COMPILE)gcc

SW_DIR ?= $(abspath ../..)
include $(SW_DIR)/isa.mk
BUILD_DIR ?= $(SW_DIR)/build/dhrystone
ITERATIONS ?= 1000
HPM ?= 0
# Performance convention: use natural four-byte code layout for all published
# measurements. Set DHRY_EXTRA_CFLAGS= to reproduce archived unaligned data.
PERF_LAYOUT_ALIGN_CFLAGS ?= -falign-functions=4 -falign-loops=4 -falign-jumps=4
DHRY_EXTRA_CFLAGS ?= $(PERF_LAYOUT_ALIGN_CFLAGS)
ELF := $(BUILD_DIR)/dhrystone.elf
IMEM_MEM := $(BUILD_DIR)/dhrystone.imem.mem
DMEM_MEM := $(BUILD_DIR)/dhrystone.dmem.mem

BSP_SRCS := $(SW_DIR)/lib/crt0.S $(SW_DIR)/lib/trap.S $(SW_DIR)/lib/trap.c \
  $(SW_DIR)/lib/uart.c $(SW_DIR)/lib/dma.c
DHRY_SRCS := dhry_1.c dhry_2.c dhry_portme.c
DHRY_OBJS := $(addprefix $(BUILD_DIR)/,$(DHRY_SRCS:.c=.o))
CFLAGS := -march=$(ISA) -mabi=$(ABI) -mcmodel=medany \
  -DERISCV_MCU_UART_DIVISOR=$(UART_DIVISOR)u \
  -ffreestanding -fno-builtin -fdata-sections -ffunction-sections \
  -Wall -Wextra -Werror -O2 -I$(SW_DIR)/include -I. \
  -DDHRY_ITERATIONS=$(ITERATIONS) -DDHRY_HPM=$(HPM) \
  $(DHRY_EXTRA_CFLAGS)
LDFLAGS := -nostdlib -nostartfiles -Wl,--gc-sections \
  -Wl,-T$(SW_DIR)/linker/eriscv_mcu.ld -Wl,-Map,$(BUILD_DIR)/dhrystone.map
LDLIBS := -lgcc

.PHONY: images clean print-config

images: $(IMEM_MEM) $(DMEM_MEM)

$(ELF): $(BSP_SRCS) $(DHRY_OBJS) | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) $(BSP_SRCS) $(DHRY_OBJS) $(LDLIBS) -o $@

$(BUILD_DIR)/%.o: %.c dhry.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(IMEM_MEM) $(DMEM_MEM): $(ELF) $(SW_DIR)/tools/elf_to_mem.py
	$(PYTHON) $(SW_DIR)/tools/elf_to_mem.py $(ELF) --imem-out $(IMEM_MEM) --dmem-out $(DMEM_MEM)

$(BUILD_DIR):
	mkdir -p $@

print-config:
	@echo "ITERATIONS=$(ITERATIONS)"
	@echo "HPM=$(HPM)"
	@echo "PERF_LAYOUT_ALIGN_CFLAGS=$(PERF_LAYOUT_ALIGN_CFLAGS)"
	@echo "DHRY_EXTRA_CFLAGS=$(DHRY_EXTRA_CFLAGS)"
	@echo "ELF=$(ELF)"
	@echo "IMEM=$(IMEM_MEM)"
	@echo "DMEM=$(DMEM_MEM)"

clean:
	rm -rf $(BUILD_DIR)
