# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

PYTHON ?= python3
FILELIST_RESOLVER = ../../../tools/project/resolve_filelist.py
AP_SOC_ROUTE_OBJ_DIR ?= /tmp/eriscv_ap_soc_route_obj
AP_SOC_SV39_FAULT_OBJ_DIR ?= /tmp/eriscv_ap_soc_sv39_fault_obj
AP_SOC_DEBUG_OBJ_DIR ?= /tmp/eriscv_ap_soc_debug_obj
VLOG ?= vlog
VSIM ?= vsim
MODELSIM_TOP ?= ap_soc_elab_tb
MODELSIM_WORK ?= work
MODELSIM_COMPILE_DO = if {![file isdirectory $(MODELSIM_WORK)]} {vlib $(MODELSIM_WORK)}; vmap $(MODELSIM_WORK) $(MODELSIM_WORK); vlog -sv -work $(MODELSIM_WORK) -f file.list; quit -f

.DEFAULT_GOAL := ap-soc-route

.PHONY: all help filelist check-filelist modelsim-compile modelsim-gui ap-soc-elab ap-soc-route ap-soc-periph-route ap-peripheral-subsystem ap-soc-sv39-route ap-soc-sv39-fault ap-soc-debug clean

all: ap-soc-route

help:
	@echo "eRISCV-AP SoC simulation"
	@echo "  make filelist          (expand AP-only RTL manifest)"
	@echo "  make check-filelist    (validate manifest paths)"
	@echo "  make ap-soc-route      (Boot ROM to I-Cache to DDR route smoke)"
	@echo "  make ap-soc-periph-route (Boot ROM to internal AXI-to-APB smoke)"
	@echo "  make ap-peripheral-subsystem (CLINT/PLIC/APB/BPI focused regression)"
	@echo "  make ap-soc-sv39-route (M-mode setup to S-mode Sv39 translated fetch)"
	@echo "  make ap-soc-sv39-fault (Sv39 instruction/data/PTE access fault routes)"
	@echo "  make ap-soc-debug      (external halt/resume route through the SoC)"
	@echo "  make modelsim-gui [MODELSIM_TOP=ap_soc_elab_tb]  (compile and open hierarchy)"
	@echo "  make ap-soc-elab       (compatibility alias for ap-soc-route)"

filelist:
	$(PYTHON) $(FILELIST_RESOLVER) filelist.f --output file.list

check-filelist:
	$(PYTHON) $(FILELIST_RESOLVER) filelist.f --check

# Run compilation through the existing WSL-to-Windows vsim bridge.  The
# bridge owns vlib/vmap/vlog, so this target does not require Linux wrappers
# for those individual ModelSim executables.
modelsim-compile: filelist
	$(VSIM) -c -do '$(MODELSIM_COMPILE_DO)'

modelsim-gui: modelsim-compile
	$(VSIM) -gui -voptargs="+acc" $(MODELSIM_WORK).$(MODELSIM_TOP)

ap-soc-route: filelist
	verilator --binary --timing -Wno-fatal -Wno-BLKANDNBLK --top-module ap_soc_elab_tb \
	  -f file.list --Mdir $(AP_SOC_ROUTE_OBJ_DIR)
	$(AP_SOC_ROUTE_OBJ_DIR)/Vap_soc_elab_tb

ap-soc-elab: ap-soc-route

ap-soc-periph-route: filelist
	verilator --binary --timing -Wno-fatal -Wno-BLKANDNBLK --top-module ap_soc_periph_route_tb \
	  -f file.list --Mdir $(AP_SOC_ROUTE_OBJ_DIR)_periph
	$(AP_SOC_ROUTE_OBJ_DIR)_periph/Vap_soc_periph_route_tb

ap-peripheral-subsystem: filelist
	verilator --binary --timing -Wno-fatal -Wno-BLKANDNBLK --top-module ap_peripheral_subsystem_tb \
	  -f file.list --Mdir $(AP_SOC_ROUTE_OBJ_DIR)_peripheral_subsystem
	$(AP_SOC_ROUTE_OBJ_DIR)_peripheral_subsystem/Vap_peripheral_subsystem_tb

ap-soc-sv39-route: filelist
	verilator --binary --timing -Wno-fatal -Wno-BLKANDNBLK --top-module ap_soc_sv39_route_tb \
	  -f file.list --Mdir $(AP_SOC_ROUTE_OBJ_DIR)_sv39
	$(AP_SOC_ROUTE_OBJ_DIR)_sv39/Vap_soc_sv39_route_tb

ap-soc-sv39-fault: filelist
	verilator --binary --timing -Wno-fatal -Wno-BLKANDNBLK --top-module ap_soc_sv39_fault_tb \
	  -f file.list --Mdir $(AP_SOC_SV39_FAULT_OBJ_DIR)
	$(AP_SOC_SV39_FAULT_OBJ_DIR)/Vap_soc_sv39_fault_tb +fault_case=1
	$(AP_SOC_SV39_FAULT_OBJ_DIR)/Vap_soc_sv39_fault_tb +fault_case=2
	$(AP_SOC_SV39_FAULT_OBJ_DIR)/Vap_soc_sv39_fault_tb +fault_case=3 +axi_read_error_addr=000080001000

ap-soc-debug: filelist
	verilator --binary --timing -Wno-fatal -Wno-BLKANDNBLK --top-module ap_soc_debug_route_tb \
	  -f file.list --Mdir $(AP_SOC_DEBUG_OBJ_DIR)
	$(AP_SOC_DEBUG_OBJ_DIR)/Vap_soc_debug_route_tb

clean:
	rm -rf $(AP_SOC_ROUTE_OBJ_DIR) file.list
