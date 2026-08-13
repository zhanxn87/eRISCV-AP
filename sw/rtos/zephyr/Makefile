# eRISCV-M2 Zephyr build wrapper
#
# Zephyr source lives in third_party/zephyr (git submodule).
# Init it once:
#   git submodule update --init third_party/zephyr
#   cd third_party/zephyr
#   pip3 install west
#   west init -l . && west update
#
# The default toolchain is the system riscv64-unknown-elf toolchain.
#
# Usage:
#   make -C rtos/zephyr images         # build + convert to .mem
#   make -C rtos/zephyr clean

PYTHON ?= python3
CROSS_COMPILE ?= riscv64-unknown-elf-
TOOLCHAIN_PREFIX := $(dir $(shell command -v $(CROSS_COMPILE)gcc))$(notdir $(CROSS_COMPILE))

SW_DIR ?= $(abspath ../..)
include $(SW_DIR)/isa.mk
THIRD_PARTY_DIR := $(abspath $(SW_DIR)/../../third_party)
ZEPHYR_PORT_DIR := $(SW_DIR)/rtos/zephyr
APP_DIR ?= $(SW_DIR)/rtos/zephyr/app
BUILD_DIR ?= $(SW_DIR)/build/zephyr
EXTRA_CONF_FILE ?=
ELF := $(BUILD_DIR)/zephyr/zephyr.elf
IMEM_MEM := $(BUILD_DIR)/zephyr.imem.mem
DMEM_MEM := $(BUILD_DIR)/zephyr.dmem.mem

# Zephyr base defaults to local third_party checkout
ZEPHYR_BASE ?= $(THIRD_PARTY_DIR)/zephyr

export ZEPHYR_BASE
export ZEPHYR_TOOLCHAIN_VARIANT = cross-compile
export CROSS_COMPILE = $(TOOLCHAIN_PREFIX)

.PHONY: images zephyr-build clean print-config

images: $(IMEM_MEM) $(DMEM_MEM)

zephyr-build: $(ELF)

$(ELF): $(APP_DIR)/CMakeLists.txt $(APP_DIR)/src/main.c $(APP_DIR)/prj.conf $(EXTRA_CONF_FILE)
	@echo "=== Zephyr build for eRISCV-M2 ==="
	@echo "ZEPHYR_BASE=$(ZEPHYR_BASE)"
	@test -d "$(ZEPHYR_BASE)" || (echo "ERROR: ZEPHYR_BASE not found: $(ZEPHYR_BASE)" && exit 1)
	@mkdir -p $(BUILD_DIR)
	cd $(BUILD_DIR) && \
	cmake \
	  -DBOARD=eriscv_mcu \
	  -DBOARD_ROOT=$(ZEPHYR_PORT_DIR) \
	  -DSOC_ROOT=$(ZEPHYR_PORT_DIR) \
	  -DDTS_ROOT=$(ZEPHYR_PORT_DIR) \
	  -DZEPHYR_TOOLCHAIN_VARIANT=cross-compile \
	  -DCROSS_COMPILE=$(TOOLCHAIN_PREFIX) \
	  -DCMAKE_C_COMPILER=$(CROSS_COMPILE)gcc \
	  -DCMAKE_CXX_COMPILER=$(CROSS_COMPILE)g++ \
	  -DCMAKE_ASM_COMPILER=$(CROSS_COMPILE)gcc \
	  -DCMAKE_AR=$(CROSS_COMPILE)ar \
	  -DCMAKE_OBJCOPY=$(CROSS_COMPILE)objcopy \
	  -DCMAKE_OBJDUMP=$(CROSS_COMPILE)objdump \
	  -DCMAKE_LINKER=$(CROSS_COMPILE)ld \
	  -DEXTRA_CONF_FILE=$(EXTRA_CONF_FILE) \
	  -DEXTRA_CFLAGS="-march=$(RTOS_ISA) -mabi=$(RTOS_ABI) -mcmodel=medany" \
	  -DEXTRA_ASMFLAGS="-march=$(RTOS_ISA) -mabi=$(RTOS_ABI) -mcmodel=medany" \
	  -DEXTRA_LDFLAGS="-nostdlib -march=$(RTOS_ISA) -mabi=$(RTOS_ABI)" \
	  $(APP_DIR) && \
	cmake --build . --target zephyr_final

$(IMEM_MEM) $(DMEM_MEM): $(ELF) $(SW_DIR)/tools/elf_to_mem.py
	$(PYTHON) $(SW_DIR)/tools/elf_to_mem.py $(ELF) --imem-out $(IMEM_MEM) --dmem-out $(DMEM_MEM)

print-config:
	@echo "ZEPHYR_BASE=$(ZEPHYR_BASE)"
	@echo "ZEPHYR_PORT_DIR=$(ZEPHYR_PORT_DIR)"
	@echo "APP_DIR=$(APP_DIR)"
	@echo "BUILD_DIR=$(BUILD_DIR)"
	@echo "ELF=$(ELF)"
	@echo "CROSS_COMPILE=$(TOOLCHAIN_PREFIX)"
	@echo "ISA=$(ISA)"
	@echo "ABI=$(ABI)"
	@echo "RTOS_ABI=$(RTOS_ABI)"
	@echo "RTOS_ISA=$(RTOS_ISA)"

clean:
	rm -rf $(BUILD_DIR)
