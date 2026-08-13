# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

PYTHON ?= python3
SIM_BACKEND ?= verilator
CROSS_COMPILE ?= riscv64-unknown-elf-
CC := $(CROSS_COMPILE)gcc

include isa.mk

EXAMPLE ?= hello_uart
VERSION ?= 0.1.0
COREMARK_ITERATIONS ?= 1
EMBENCH_BENCH ?= matmult-int
EMBENCH_PROFILE ?= speed
EMBENCH_SCALE ?= 1
DHRY_ITERATIONS ?= 1000
DHRY_HPM ?= 0
LINPACK_ORDER ?= 32
LINPACK_REPETITIONS ?= 1
# Applied only to benchmark-style examples (currently the floating-point FFT).
# General software and functional-regression images keep their existing layout.
PERF_LAYOUT_ALIGN_CFLAGS ?= -falign-functions=4 -falign-loops=4 -falign-jumps=4
RELEASE_EXAMPLES := hello_uart timer_apb_poll timer_clint wfi_tickless irq_timer_uart wdt_smoke dma_system_sram dma_irq_wfi dma_descriptor_chain dma_descriptor_irq_wfi fpu_dma_sram dma_uart_tx fpu_fft
BUILD_DIR ?= build/$(EXAMPLE)
ELF := $(BUILD_DIR)/$(EXAMPLE).elf
IMEM_MEM := $(BUILD_DIR)/$(EXAMPLE).imem.mem
DMEM_MEM := $(BUILD_DIR)/$(EXAMPLE).dmem.mem

COMMON_SRCS := lib/crt0.S lib/trap.S lib/trap.c lib/uart.c lib/dma.c
EXAMPLE_SRC := examples/$(EXAMPLE)/main.c
CFLAGS := -march=$(ISA) -mabi=$(ABI) -mcmodel=medany \
  -DERISCV_MCU_UART_DIVISOR=$(UART_DIVISOR)u \
  -ffreestanding -fno-builtin -fdata-sections -ffunction-sections \
  -Wall -Wextra -Werror -Os -Iinclude
ifneq ($(filter fpu_fft fpu_fft1024,$(EXAMPLE)),)
CFLAGS += -ffp-contract=off $(PERF_LAYOUT_ALIGN_CFLAGS)
endif

LDFLAGS := -nostdlib -nostartfiles -Wl,--gc-sections -Wl,-Tlinker/eriscv_mcu.ld \
  -Wl,-Map,$(BUILD_DIR)/$(EXAMPLE).map

.PHONY: all fpu-fft-vectors images images-all ci sim sim-async sim-fpu-dma-sram sim-dma-uart-tx sim-fpu-fft sim-fpu-fft1024 sim-fpu-fft1024-mcycle sim-mcycle-counter coremark sim-coremark embench sim-embench embench-suite microbench sim-microbench linpack sim-linpack freertos sim-freertos sim-freertos-qualification freertos-umode sim-freertos-umode dhrystone sim-dhrystone zephyr sim-zephyr clean print-config

all: images

images: $(IMEM_MEM) $(DMEM_MEM)

images-all:
	@for example in $(RELEASE_EXAMPLES); do \
	  $(MAKE) EXAMPLE=$$example images || exit $$?; \
	done

ci: images-all
	$(PYTHON) tools/run_mcu_ci.py --skip-build

sim: images
	$(PYTHON) tools/run_hello_uart_sim.py --backend $(SIM_BACKEND)

sim-async:
	$(PYTHON) tools/run_hello_uart_sim.py --backend $(SIM_BACKEND) --example async_uart --tc BSP-UART-ASYNC --expected-uart 655249534356204d4355206173796e63205541525420495251204649464f20736d6f6b653a20303132333435363738396162636465666768696a6b6c6d6e6f707172737475767778797a4142434445464748494a4b4c4d4e4f505152535455565758595a0d0a --max-cycles 20000

sim-fpu-dma-sram:
	$(PYTHON) tools/run_hello_uart_sim.py --backend $(SIM_BACKEND) --example fpu_dma_sram --tc BSP-FPU-DMA-SRAM --expected-uart 6552495343562d4d322046505520444d41205352414d20504153530d0a --max-cycles 20000

sim-dma-uart-tx:
	$(PYTHON) tools/run_hello_uart_sim.py --backend $(SIM_BACKEND) --example dma_uart_tx --tc BSP-DMA-UART-TX --expected-uart 444d41205541525420545820504153530a --max-cycles 20000

sim-fpu-fft:
	$(PYTHON) tools/run_hello_uart_sim.py --backend $(SIM_BACKEND) --example fpu_fft --tc BSP-FPU-FFT128 --expected-uart 6552495343562d4d32204650552046465431323820504153530d0a --expected-gpio-out 1 --expected-gpio-oe 1 --max-cycles 120000

sim-fpu-fft1024:
	$(PYTHON) tools/run_hello_uart_sim.py --backend $(SIM_BACKEND) --example fpu_fft1024 --tc BSP-FPU-FFT1024 --expected-uart 6552495343562d4d3220465055204646543130323420504153530d0a --expected-gpio-out 1 --expected-gpio-oe 1 --max-cycles 1600000

sim-fpu-fft1024-mcycle:
	$(PYTHON) tools/run_fpu_fft_mcycle_sim.py --example fpu_fft1024 --points 1024

sim-mcycle-counter:
	$(PYTHON) tools/run_mcycle_counter_sim.py

coremark:
	$(MAKE) -C benchmarks/coremark SW_DIR=$(CURDIR) ISA=$(ISA) ABI=$(ABI) SOC_CLOCK_HZ=$(SOC_CLOCK_HZ) UART_DIVISOR=$(UART_DIVISOR) ITERATIONS=$(COREMARK_ITERATIONS) images

sim-coremark:
	$(PYTHON) tools/run_coremark_sim.py --iterations $(COREMARK_ITERATIONS) --backend $(SIM_BACKEND)

embench:
	$(MAKE) -C benchmarks/embench SW_DIR=$(CURDIR) ISA=$(ISA) ABI=$(ABI) UART_DIVISOR=$(UART_DIVISOR) BENCH=$(EMBENCH_BENCH) PROFILE=$(EMBENCH_PROFILE) SCALE=$(EMBENCH_SCALE) images

sim-embench:
	$(PYTHON) tools/run_embench_sim.py --backend $(SIM_BACKEND)

embench-suite:
	$(PYTHON) tools/run_embench_sim.py --suite --backend $(SIM_BACKEND)

microbench:
	$(MAKE) -C benchmarks/microbench SW_DIR=$(CURDIR) ISA=$(ISA) ABI=$(ABI) UART_DIVISOR=$(UART_DIVISOR) images

sim-microbench:
	$(PYTHON) tools/run_microbench_sim.py

linpack:
	$(MAKE) -C benchmarks/linpack SW_DIR=$(CURDIR) ISA=$(ISA) ABI=$(ABI) UART_DIVISOR=$(UART_DIVISOR) ORDER=$(LINPACK_ORDER) REPETITIONS=$(LINPACK_REPETITIONS) images

sim-linpack:
	$(PYTHON) tools/run_linpack_sim.py --backend $(SIM_BACKEND) --order $(LINPACK_ORDER) --repetitions $(LINPACK_REPETITIONS)

freertos:
	$(MAKE) -C rtos/freertos SW_DIR=$(CURDIR) RTOS_ISA=$(RTOS_ISA) RTOS_ABI=$(RTOS_ABI) UART_DIVISOR=$(UART_DIVISOR) images

sim-freertos:
	$(PYTHON) tools/run_freertos_sim.py

sim-freertos-qualification:
	$(PYTHON) tools/run_freertos_sim.py --failstops

freertos-umode:
	$(MAKE) -C rtos/freertos_umode SW_DIR=$(CURDIR) RTOS_ISA=$(RTOS_ISA) RTOS_ABI=$(RTOS_ABI) UART_DIVISOR=$(UART_DIVISOR) images

sim-freertos-umode:
	$(PYTHON) tools/run_freertos_umode_sim.py

dhrystone:
	$(MAKE) -C benchmarks/dhrystone SW_DIR=$(CURDIR) ISA=$(ISA) ABI=$(ABI) UART_DIVISOR=$(UART_DIVISOR) ITERATIONS=$(DHRY_ITERATIONS) HPM=$(DHRY_HPM) images

sim-dhrystone:
	$(PYTHON) tools/run_dhrystone_sim.py

zephyr:
	$(MAKE) -C rtos/zephyr SW_DIR=$(CURDIR) RTOS_ISA=$(RTOS_ISA) RTOS_ABI=$(RTOS_ABI) images

sim-zephyr:
	$(PYTHON) tools/run_zephyr_sim.py

fpu-fft-vectors:
	$(PYTHON) tools/generate_fpu_fft_vectors.py --points 128
	$(PYTHON) tools/generate_fpu_fft_vectors.py --points 1024

$(ELF): $(COMMON_SRCS) $(EXAMPLE_SRC) linker/eriscv_mcu.ld examples/fpu_fft/fpu_fft128_vectors.h examples/fpu_fft1024/fpu_fft1024_vectors.h examples/fpu_fft/fft_main.inc | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) $(COMMON_SRCS) $(EXAMPLE_SRC) -o $@

$(IMEM_MEM) $(DMEM_MEM): $(ELF) tools/elf_to_mem.py
	$(PYTHON) tools/elf_to_mem.py $(ELF) --imem-out $(IMEM_MEM) --dmem-out $(DMEM_MEM)

$(BUILD_DIR):
	mkdir -p $@

print-config:
	@echo "VERSION=$(VERSION)"
	@echo "EXAMPLE=$(EXAMPLE)"
	@echo "CROSS_COMPILE=$(CROSS_COMPILE)"
	@echo "ISA=$(ISA)"
	@echo "ABI=$(ABI)"
	@echo "RTOS_ABI=$(RTOS_ABI)"
	@echo "RTOS_ISA=$(RTOS_ISA)"
	@echo "SOC_CLOCK_HZ=$(SOC_CLOCK_HZ)"
	@echo "UART_MODE=$(UART_MODE)"
	@echo "UART_DIVISOR=$(UART_DIVISOR)"
	@echo "PERF_LAYOUT_ALIGN_CFLAGS=$(PERF_LAYOUT_ALIGN_CFLAGS)"
	@echo "UART_BOARD_DIVISOR=$(UART_BOARD_DIVISOR)"
	@echo "IMEM=$(IMEM_MEM)"
	@echo "DMEM=$(DMEM_MEM)"

clean:
	rm -rf build
