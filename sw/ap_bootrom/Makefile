# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

PYTHON ?= python3
CROSS_COMPILE ?= riscv64-unknown-elf-
CC := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy

BUILD_DIR ?= build
PAYLOAD_LOAD_ADDR ?= 0x0000000080001000
PAYLOAD_SOURCE ?= payload.S
PAYLOAD_LINKER ?= payload.ld

COMMON_FLAGS := -march=rv64imac_zicsr_zifencei -mabi=lp64 -mno-relax \
  -nostdlib -nostartfiles -ffreestanding -fno-builtin -Wall -Wextra -Werror
BOOT_ELF := $(BUILD_DIR)/bootrom.elf
BOOT_ROM_MEM := $(BUILD_DIR)/bootrom.mem
PAYLOAD_ELF := $(BUILD_DIR)/payload.elf
PAYLOAD_BIN := $(BUILD_DIR)/payload.bin
BPI_IMAGE := $(BUILD_DIR)/boot_payload.bpi.mem

.DEFAULT_GOAL := images

.PHONY: all images clean

all: images

images: $(BOOT_ROM_MEM) $(BPI_IMAGE)

$(BOOT_ELF): boot.S boot.ld | $(BUILD_DIR)
	$(CC) $(COMMON_FLAGS) -Wl,-T,boot.ld -Wl,--build-id=none -o $@ $<

$(BOOT_ROM_MEM): $(BOOT_ELF)
	$(OBJCOPY) -O verilog --verilog-data-width=4 $< $@

$(PAYLOAD_ELF): $(PAYLOAD_SOURCE) $(PAYLOAD_LINKER) | $(BUILD_DIR)
	$(CC) $(COMMON_FLAGS) -Wl,-T,$(PAYLOAD_LINKER) -Wl,--build-id=none -o $@ $(PAYLOAD_SOURCE)

$(PAYLOAD_BIN): $(PAYLOAD_ELF)
	$(OBJCOPY) -O binary $< $@

$(BPI_IMAGE): $(PAYLOAD_BIN) mk_bpi_image.py
	$(PYTHON) mk_bpi_image.py --payload-bin $< --output $@ \
	  --load-addr $(PAYLOAD_LOAD_ADDR) --entry-addr $(PAYLOAD_LOAD_ADDR)

$(BUILD_DIR):
	mkdir -p $@

clean:
	rm -rf $(BUILD_DIR)
