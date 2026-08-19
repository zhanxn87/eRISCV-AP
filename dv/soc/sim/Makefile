# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

PYTHON ?= python3
VERILATOR_JOBS ?= 8
FILELIST_RESOLVER = ../../../tools/project/resolve_filelist.py
AP_SOC_ROUTE_OBJ_DIR ?= /tmp/eriscv_ap_soc_route_obj
AP_SOC_SV39_FAULT_OBJ_DIR ?= /tmp/eriscv_ap_soc_sv39_fault_obj
AP_SOC_DEBUG_OBJ_DIR ?= /tmp/eriscv_ap_soc_debug_obj
AP_SOC_FLASH_BOOT_OBJ_DIR ?= /tmp/eriscv_ap_soc_flash_boot_obj
AP_SOC_FLASH_BOOT_EXTENDED_OBJ_DIR ?= /tmp/eriscv_ap_soc_flash_boot_extended_obj
AP_SOC_FLASH_BOOT_SV39_OBJ_DIR ?= /tmp/eriscv_ap_soc_flash_boot_sv39_obj
AP_BOOTROM_DIR ?= ../../../sw/ap_bootrom
VLOG ?= vlog
VSIM ?= vsim
MODELSIM_TOP ?= ap_soc_elab_tb
MODELSIM_WORK ?= work
MODELSIM_COMPILE_DO = if {![file isdirectory $(MODELSIM_WORK)]} {vlib $(MODELSIM_WORK)}; vmap $(MODELSIM_WORK) $(MODELSIM_WORK); vlog -sv -work $(MODELSIM_WORK) -f file.list; quit -f

.DEFAULT_GOAL := ap-soc-route

.PHONY: all help filelist check-filelist modelsim-compile modelsim-gui ap-soc-elab ap-soc-route ap-soc-flash-boot ap-soc-flash-boot-extended ap-soc-flash-boot-wait ap-soc-flash-boot-invalid ap-soc-flash-boot-regression ap-soc-flash-boot-sv39 ap-soc-periph-route ap-peripheral-subsystem ap-soc-sv39-route ap-soc-sv39-fault ap-soc-debug eth-mac-lint ap-ethernet-dma ap-ethernet-ring clean

all: ap-soc-route

help:
	@echo "eRISCV-AP SoC simulation"
	@echo "  make filelist          (expand AP-only RTL manifest)"
	@echo "  make check-filelist    (validate manifest paths)"
	@echo "  make ap-soc-route      (Boot ROM to I-Cache to DDR route smoke)"
	@echo "  make ap-soc-flash-boot (Boot ROM -> BPI NOR -> DDR -> payload regression)"
	@echo "  make ap-soc-flash-boot-regression (boot copy, checksum, FENCE.I, BPI wait, negative images)"
	@echo "  make ap-soc-flash-boot-sv39 (complete Boot ROM -> BPI -> DDR -> S-mode Sv39 route)"
	@echo "  make ap-soc-periph-route (Boot ROM to internal AXI-to-APB smoke)"
	@echo "  make ap-peripheral-subsystem (CLINT/PLIC/APB/BPI focused regression)"
	@echo "  make ap-soc-sv39-route (M-mode setup to S-mode Sv39 translated fetch)"
	@echo "  make ap-soc-sv39-fault (Sv39 instruction/data/PTE access fault routes)"
	@echo "  make ap-soc-debug      (external halt/resume route through the SoC)"
	@echo "  make eth-mac-lint      (MIT 1G MAC closure and namespace check)"
	@echo "  make ap-ethernet-dma   (descriptor rings, AXI64 DMA, CDC, GMII TX/FCS and CRC-valid RX)"
	@echo "  make ap-ethernet-ring  (alias for ap-ethernet-dma)"
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

# Keep the vendored MAC source closure checked independently from the APB/DMA
# integration regression.  Upstream parameterized PTP paths
# trigger only width/case/timescale diagnostics under Verilator 5.020; binding errors
# remain fatal here.
eth-mac-lint:
	verilator --lint-only -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
	  -Wno-SELRANGE -Wno-CASEINCOMPLETE -Wno-TIMESCALEMOD -Werror-MODDUP -Werror-PINMISSING \
	  --top-module eth_mac_1g \
	  ../../../rtl/vendor/common_cells/src/lfsr.sv \
	  ../../../rtl/vendor/verilog_ethernet/rtl/ap_eth_lfsr.v \
	  ../../../rtl/vendor/verilog_ethernet/rtl/axis_gmii_rx.v \
	  ../../../rtl/vendor/verilog_ethernet/rtl/axis_gmii_tx.v \
	  ../../../rtl/vendor/verilog_ethernet/rtl/eth_mac_1g.v

ap-soc-route: filelist
	verilator --binary --timing -Wno-fatal -Wno-BLKANDNBLK --top-module ap_soc_elab_tb \
	  -f file.list --Mdir $(AP_SOC_ROUTE_OBJ_DIR)
	$(AP_SOC_ROUTE_OBJ_DIR)/Vap_soc_elab_tb

ap-soc-elab: ap-soc-route

ap-soc-flash-boot: filelist
	$(MAKE) -C $(AP_BOOTROM_DIR) images
	verilator --binary --timing -Wno-fatal -Wno-BLKANDNBLK --top-module ap_soc_flash_boot_tb \
	  -f file.list --Mdir $(AP_SOC_FLASH_BOOT_OBJ_DIR)
	$(AP_SOC_FLASH_BOOT_OBJ_DIR)/Vap_soc_flash_boot_tb

ap-soc-flash-boot-extended: filelist
	$(MAKE) -C $(AP_BOOTROM_DIR) images
	verilator --binary --timing -Wno-fatal -Wno-BLKANDNBLK --top-module ap_soc_flash_boot_extended_tb \
	  -f file.list --Mdir $(AP_SOC_FLASH_BOOT_EXTENDED_OBJ_DIR)
	$(AP_SOC_FLASH_BOOT_EXTENDED_OBJ_DIR)/Vap_soc_flash_boot_extended_tb

ap-soc-flash-boot-wait: ap-soc-flash-boot-extended
	$(AP_SOC_FLASH_BOOT_EXTENDED_OBJ_DIR)/Vap_soc_flash_boot_extended_tb +bpi_ready_delay=64

ap-soc-flash-boot-invalid: ap-soc-flash-boot-extended
	$(AP_SOC_FLASH_BOOT_EXTENDED_OBJ_DIR)/Vap_soc_flash_boot_extended_tb +bad_image=magic
	$(AP_SOC_FLASH_BOOT_EXTENDED_OBJ_DIR)/Vap_soc_flash_boot_extended_tb +bad_image=version
	$(AP_SOC_FLASH_BOOT_EXTENDED_OBJ_DIR)/Vap_soc_flash_boot_extended_tb +bad_image=size
	$(AP_SOC_FLASH_BOOT_EXTENDED_OBJ_DIR)/Vap_soc_flash_boot_extended_tb +bad_image=load
	$(AP_SOC_FLASH_BOOT_EXTENDED_OBJ_DIR)/Vap_soc_flash_boot_extended_tb +bad_image=entry
	$(AP_SOC_FLASH_BOOT_EXTENDED_OBJ_DIR)/Vap_soc_flash_boot_extended_tb +bad_image=checksum

ap-soc-flash-boot-regression: ap-soc-flash-boot-extended ap-soc-flash-boot-wait ap-soc-flash-boot-invalid

ap-soc-flash-boot-sv39: filelist
	$(MAKE) -C $(AP_BOOTROM_DIR) BUILD_DIR=build/sv39 PAYLOAD_SOURCE=payload_sv39.S PAYLOAD_LINKER=payload_sv39.ld PAYLOAD_LOAD_ADDR=0x0000000080010000 images
	verilator --binary --timing -Wno-fatal -Wno-BLKANDNBLK --top-module ap_soc_flash_boot_sv39_tb \
	  -f file.list --Mdir $(AP_SOC_FLASH_BOOT_SV39_OBJ_DIR)
	$(AP_SOC_FLASH_BOOT_SV39_OBJ_DIR)/Vap_soc_flash_boot_sv39_tb

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

ap-ethernet-dma: filelist
	verilator --binary --timing -j $(VERILATOR_JOBS) -Wno-fatal -Wno-BLKANDNBLK --top-module ap_ethernet_dma_tb \
          -f file.list --Mdir $(AP_SOC_ROUTE_OBJ_DIR)_ethernet_dma
	$(AP_SOC_ROUTE_OBJ_DIR)_ethernet_dma/Vap_ethernet_dma_tb

ap-ethernet-ring: ap-ethernet-dma

ap-soc-debug: filelist
	verilator --binary --timing -Wno-fatal -Wno-BLKANDNBLK --top-module ap_soc_debug_route_tb \
	  -f file.list --Mdir $(AP_SOC_DEBUG_OBJ_DIR)
	$(AP_SOC_DEBUG_OBJ_DIR)/Vap_soc_debug_route_tb

clean:
	rm -rf $(AP_SOC_ROUTE_OBJ_DIR) file.list
