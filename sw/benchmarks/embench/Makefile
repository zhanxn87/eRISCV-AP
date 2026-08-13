# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

PYTHON ?= python3
CROSS_COMPILE ?= riscv64-unknown-elf-
CC := $(CROSS_COMPILE)gcc

SW_DIR ?= $(abspath ../..)
include $(SW_DIR)/isa.mk
THIRD_PARTY_DIR := $(abspath $(SW_DIR)/../../third_party)
EMBENCH_DIR := $(THIRD_PARTY_DIR)/embench-iot
BENCH ?= matmult-int
PROFILE ?= speed
SCALE ?= 1
BUILD_DIR ?= $(SW_DIR)/build/embench/$(PROFILE)/$(BENCH)/scale-$(SCALE)
# Performance convention: speed-profile images use four-byte code layout.
# Size-profile artifacts intentionally leave this empty.
PERF_LAYOUT_ALIGN_CFLAGS ?= -falign-functions=4 -falign-loops=4 -falign-jumps=4
ELF := $(BUILD_DIR)/$(BENCH).elf
IMEM_MEM := $(BUILD_DIR)/$(BENCH).imem.mem
DMEM_MEM := $(BUILD_DIR)/$(BENCH).dmem.mem

ifeq ($(PROFILE),speed)
OPTIMIZATION := -O2
PERF_CFLAGS := $(PERF_LAYOUT_ALIGN_CFLAGS)
else ifeq ($(PROFILE),size)
OPTIMIZATION := -Os
PERF_CFLAGS :=
else
$(error PROFILE must be speed or size)
endif

BSP_SRCS := $(SW_DIR)/lib/crt0.S $(SW_DIR)/lib/trap.S $(SW_DIR)/lib/trap.c \
  $(SW_DIR)/lib/uart.c $(SW_DIR)/lib/dma.c $(SW_DIR)/rtos/freertos/freertos_libc.c
SUPPORT_SRCS := $(EMBENCH_DIR)/support/beebsc.c embench_port.c embench_libc.c
UPSTREAM_BENCH_SRCS := $(sort $(wildcard $(EMBENCH_DIR)/src/$(BENCH)/*.c))
BENCH_SRCS := $(patsubst $(EMBENCH_DIR)/src/%, $(BUILD_DIR)/src/%, $(UPSTREAM_BENCH_SRCS))
CFLAGS := -march=$(ISA) -mabi=$(ABI) -mcmodel=medany \
  -DERISCV_MCU_UART_DIVISOR=$(UART_DIVISOR)u \
  -ffreestanding -fno-builtin -fdata-sections -ffunction-sections \
  -Wall -Wextra $(OPTIMIZATION) $(PERF_CFLAGS) -I. -I$(SW_DIR)/include -I$(SW_DIR)/rtos/freertos \
  -I$(EMBENCH_DIR)/support -I$(EMBENCH_DIR)/src/$(BENCH) \
  -DCPU_MHZ=1 -DWARMUP_HEAT=0
LDFLAGS := -nostdlib -nostartfiles -Wl,--gc-sections \
  -Wl,-T$(SW_DIR)/linker/eriscv_mcu.ld -Wl,-Map,$(BUILD_DIR)/$(BENCH).map
LDLIBS := -lgcc

ifeq ($(strip $(UPSTREAM_BENCH_SRCS)),)
$(error Unknown Embench workload: $(BENCH))
endif

.PHONY: images clean print-config

images: $(IMEM_MEM) $(DMEM_MEM)

$(ELF): $(BSP_SRCS) $(SUPPORT_SRCS) $(BENCH_SRCS) | $(BUILD_DIR)

	$(CC) $(CFLAGS) $(LDFLAGS) $(BSP_SRCS) $(SUPPORT_SRCS) $(BENCH_SRCS) $(LDLIBS) -o $@

$(BUILD_DIR)/src/%.c: $(EMBENCH_DIR)/src/%.c | $(BUILD_DIR)
	mkdir -p $(dir $@)
	sed -e 's/^#define LOCAL_SCALE_FACTOR[[:space:]][[:space:]]*[0-9][0-9]*/#define LOCAL_SCALE_FACTOR $(SCALE)/' $< > $@

$(BUILD_DIR)/src/wikisort/libwikisort.c: $(EMBENCH_DIR)/src/wikisort/libwikisort.c | $(BUILD_DIR)
	mkdir -p $(dir $@)
	sed -e 's/^#define LOCAL_SCALE_FACTOR[[:space:]][[:space:]]*[0-9][0-9]*/#define LOCAL_SCALE_FACTOR $(SCALE)/' \
		-e 's@^#include <string.h>@#include <string.h>\n#include <stdbool.h>@' $< > $@

$(IMEM_MEM) $(DMEM_MEM): $(ELF) $(SW_DIR)/tools/elf_to_mem.py
	$(PYTHON) $(SW_DIR)/tools/elf_to_mem.py $(ELF) --imem-out $(IMEM_MEM) --dmem-out $(DMEM_MEM)

$(BUILD_DIR):
	mkdir -p $@

print-config:
	@echo "BENCH=$(BENCH)"
	@echo "PROFILE=$(PROFILE)"
	@echo "SCALE=$(SCALE)"
	@echo "PERF_LAYOUT_ALIGN_CFLAGS=$(PERF_CFLAGS)"
	@echo "ELF=$(ELF)"
	@echo "IMEM=$(IMEM_MEM)"
	@echo "DMEM=$(DMEM_MEM)"

clean:
	rm -rf $(SW_DIR)/build/embench
