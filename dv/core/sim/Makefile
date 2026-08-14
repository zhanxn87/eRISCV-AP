# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

PYTHON ?= python3
BROWSER ?= firefox
BACKEND ?= verilator
TESTS ?=
MODELSIM_GUI_TEST ?=
WAVE ?= $(shell find visual_waves waves -maxdepth 1 -type f \( -name '*.fst' -o -name '*.vcd' -o -name '*.ghw' \) -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
FULL_TESTS ?= --directed-only --act-full
SMOKE_TESTS ?= --directed-only --compliance-smoke --act-smoke
RV64_TESTS = MCU-RV64-CORE-01 MCU-RV64-ALU-CFLOW-01 MCU-RV64-M-01 MCU-RV64-LDST-01 MCU-RV64-C-CROSSWORD-01 MCU-RV64-FD-MOVE-01 MCU-RV64-FD-01 MCU-RV64-A-01 MCU-RV64-FENCE-01
RV64_OBJ_DIR ?= /tmp/eriscv_ap_rv64_directed_obj
RV64_MAX_CYCLES ?= 1600
REGRESSION_FLAGS = $(if $(filter full,$(MAKECMDGOALS)),$(FULL_TESTS),$(if $(filter smoke,$(MAKECMDGOALS)),$(SMOKE_TESTS),$(TESTS)))

FILELIST_RESOLVER = ../../../tools/project/resolve_filelist.py

.DEFAULT_GOAL := verilator

.PHONY: all help filelist check-filelist list verilator modelsim modelsim-gui auto wave visual surfer full smoke rv64-directed bht-predictor icache dcache cache-axi clean

all: verilator

help:
	@echo "eRISCV-M2 simulation shortcuts"
	@echo
	@echo "Inspect:"
	@echo "  make filelist"
	@echo "  make check-filelist"
	@echo "  make list"
	@echo
	@echo "Run regressions:"
	@echo "  make                         (Verilator directed + smoke regression)"
	@echo "  make modelsim [TESTS=P1-ALU-01]  (focused batch debug)"
	@echo "  make modelsim-gui MODELSIM_GUI_TEST=P1-ALU-01"
	@echo "  make full [BACKEND=verilator]"
	@echo "  make smoke"
	@echo "  make rv64-directed          (RV64I/M/C directed regression)"
	@echo "  make verilator [TESTS=P1-ALU-01]"
	@echo "  make auto      [TESTS=P1-ALU-01]"
	@echo "  make cache-axi              (64-bit AXI4 cache-line transport unit test)"
	@echo "  make bht-predictor              (focused 64-entry BHT unit test)"
	@echo "  make icache                     (32KiB/2-way/64B I-Cache unit test)"
	@echo "  make dcache                     (32KiB/2-way/64B D-Cache unit test)"
	@echo
	@echo "Clean:"
	@echo "  make clean"

filelist:
	$(PYTHON) $(FILELIST_RESOLVER) filelist.f --output file.list

check-filelist:
	$(PYTHON) $(FILELIST_RESOLVER) filelist.f --check

list: filelist
	$(PYTHON) run_regression.py --list-tests

full:
	$(MAKE) $(BACKEND) TESTS="$(FULL_TESTS)"

smoke:
	$(MAKE) $(BACKEND) TESTS="$(SMOKE_TESTS)"

rv64-directed: filelist
	verilator --binary --timing -Wno-fatal -Wno-BLKANDNBLK --top-module riscv_tb -f file.list --Mdir $(RV64_OBJ_DIR)
	@for tc in $(RV64_TESTS); do \
	  extra_args=""; \
	  if test -f ../tests/RV64/$$tc.fence; then \
	    extra_args="+fence_check_file=../tests/RV64/$$tc.fence"; \
	  fi; \
	  $(RV64_OBJ_DIR)/Vriscv_tb +tc=$$tc +instr_mem_file=../tests/RV64/$$tc.mem +expected_regs_file=../tests/RV64/$$tc.expected $$extra_args +max_cycles=$(RV64_MAX_CYCLES) || exit $$?; \
	done

verilator:
	$(PYTHON) run_regression.py --backend verilator $(REGRESSION_FLAGS)

modelsim:
	$(PYTHON) run_regression.py --backend modelsim $(REGRESSION_FLAGS)

modelsim-gui:
	@test -n "$(MODELSIM_GUI_TEST)" || (echo "Set MODELSIM_GUI_TEST=<directed testcase>"; exit 2)
	$(PYTHON) run_regression.py --modelsim-gui-test "$(MODELSIM_GUI_TEST)"

auto:
	$(PYTHON) run_regression.py --backend auto $(REGRESSION_FLAGS)

bht-predictor:
	rm -rf obj_dir_bht
	verilator --binary --timing --Wno-TIMESCALEMOD --top-module branch_predictor_tb ../../../rtl/riscv_core/return_address_stack.sv ../../../rtl/riscv_core/branch_predictor.sv ../tb/branch_predictor_tb.sv --Mdir obj_dir_bht
	./obj_dir_bht/Vbranch_predictor_tb

cache-axi:
	verilator --binary --timing -Wno-fatal --top-module cache_axi4_line_adapter_tb ../../../rtl/soc/axi/cache_axi4_line_adapter.sv ../tb/cache_axi4_line_adapter_tb.sv --Mdir /tmp/eriscv_ap_cache_axi_obj
	/tmp/eriscv_ap_cache_axi_obj/Vcache_axi4_line_adapter_tb

icache:
	verilator --binary --timing -Wno-fatal --top-module icache_tb ../../../rtl/soc/cache/icache.sv ../tb/dcache_line_mem.sv ../tb/icache_tb.sv --Mdir /tmp/eriscv_ap_icache_obj
	/tmp/eriscv_ap_icache_obj/Vicache_tb

dcache:
	verilator --binary --timing -Wno-fatal --top-module dcache_tb ../../../rtl/soc/cache/dcache.sv ../tb/dcache_line_mem.sv ../tb/dcache_tb.sv --Mdir /tmp/eriscv_ap_dcache_obj
	/tmp/eriscv_ap_dcache_obj/Vdcache_tb

wave:
	$(PYTHON) run_regression.py --backend verilator --wave --dump-format fst --wave-dir visual_waves $(TESTS)

visual:
	$(PYTHON) ../../../../tools/sim/run_visual_phase.py --sim-dir . $(TESTS)

clean:
	rm -rf obj_dir regression_logs visual_waves waves work transcript *.log .modelsim_work_cache.json
