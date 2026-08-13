# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

PYTHON ?= python3
TESTS ?=
FILELIST_RESOLVER = ../../../tools/project/resolve_filelist.py

.DEFAULT_GOAL := verilator

RV64_WIDTH_ADAPTER_OBJ_DIR ?= /tmp/eriscv_ap_soc_width_obj
RV64_DEBUG_OBJ_DIR ?= /tmp/eriscv_ap_rv64_debug_obj

.PHONY: all help filelist check-filelist list verilator modelsim auto rv64-width-adapter rv64-debug-module tcm-arbitration dma-system-sram dma-uart-tx clean

all: verilator

help:
	@echo "eRISCV-M2 SoC simulation"
	@echo
	@echo "Inspect:"
	@echo "  make filelist"
	@echo "  make check-filelist"
	@echo "  make list"
	@echo
	@echo "Build and run:"
	@echo "  make                         (Verilator directed regression)"
	@echo "  make modelsim [TESTS=SOC-SMOKE-01]"
	@echo "  make tcm-arbitration"
	@echo "  make dma-system-sram"
	@echo "  make verilator [TESTS=SOC-SMOKE-01]"
	@echo "  make auto      [TESTS=SOC-SMOKE-01]"
	@echo "  make rv64-width-adapter  (RV64 48-bit/64-bit SoC boundary TB)"
	@echo "  make rv64-debug-module   (RV64 Debug Module abstract-register TB)"
	@echo "  make clean  (remove the incremental Verilator cache)"

filelist:
	$(PYTHON) $(FILELIST_RESOLVER) filelist.f --output file.list

check-filelist:
	$(PYTHON) $(FILELIST_RESOLVER) filelist.f --check

list: filelist
	$(PYTHON) run_regression.py --list-tests

verilator:
	$(PYTHON) run_regression.py --backend verilator $(TESTS)

modelsim:
	$(PYTHON) run_regression.py --backend modelsim $(TESTS)

auto:
	$(PYTHON) run_regression.py --backend auto $(TESTS)

rv64-width-adapter:
	verilator --binary --timing -Wno-fatal --top-module rv64_soc_width_adapter_tb \
	  ../../../rtl/soc/bus/dbus64_to_dbus32_adapter.sv \
	  ../../../rtl/soc/mem/lmem64_to_lmem32_adapter.sv \
	  ../../../rtl/soc/bus/ibus48_to_ibus32_adapter.sv \
	  ../tb/rv64_soc_width_adapter_tb.sv --Mdir $(RV64_WIDTH_ADAPTER_OBJ_DIR)
	$(RV64_WIDTH_ADAPTER_OBJ_DIR)/Vrv64_soc_width_adapter_tb

rv64-debug-module:
	verilator --binary --timing -Wno-fatal --top-module rv64_debug_module_tb \
	  ../../../rtl/soc/debug/debug_module_min.sv ../tb/rv64_debug_module_tb.sv \
	  --Mdir $(RV64_DEBUG_OBJ_DIR)
	$(RV64_DEBUG_OBJ_DIR)/Vrv64_debug_module_tb

tcm-arbitration: filelist
	vsim -c -do run_tcm_arbitration.do

dma-system-sram: filelist
	vsim -c -do run_dma_system_sram.do

dma-uart-tx: filelist
	vsim -c -do run_dma_uart_tx.do

clean:
	rm -rf obj_dir regression_logs visual_waves waves work transcript *.log .modelsim_work_cache.json
