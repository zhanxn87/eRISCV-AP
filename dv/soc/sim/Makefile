# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

PYTHON ?= python3
FILELIST_RESOLVER = ../../../tools/project/resolve_filelist.py
AP_SOC_ROUTE_OBJ_DIR ?= /tmp/eriscv_ap_soc_route_obj

.DEFAULT_GOAL := ap-soc-route

.PHONY: all help filelist check-filelist ap-soc-elab ap-soc-route ap-soc-periph-route clean

all: ap-soc-route

help:
	@echo "eRISCV-AP SoC simulation"
	@echo "  make filelist          (expand AP-only RTL manifest)"
	@echo "  make check-filelist    (validate manifest paths)"
	@echo "  make ap-soc-route      (Boot ROM to I-Cache to DDR route smoke)"
	@echo "  make ap-soc-periph-route (Boot ROM to uncached axi_periph smoke)"
	@echo "  make ap-soc-elab       (compatibility alias for ap-soc-route)"

filelist:
	$(PYTHON) $(FILELIST_RESOLVER) filelist.f --output file.list

check-filelist:
	$(PYTHON) $(FILELIST_RESOLVER) filelist.f --check

ap-soc-route: filelist
	verilator --binary --timing -Wno-fatal -Wno-BLKANDNBLK --top-module ap_soc_elab_tb \
	  -f file.list --Mdir $(AP_SOC_ROUTE_OBJ_DIR)
	$(AP_SOC_ROUTE_OBJ_DIR)/Vap_soc_elab_tb

ap-soc-elab: ap-soc-route

ap-soc-periph-route: filelist
	verilator --binary --timing -Wno-fatal -Wno-BLKANDNBLK --top-module ap_soc_periph_route_tb \
	  -f file.list --Mdir $(AP_SOC_ROUTE_OBJ_DIR)_periph
	$(AP_SOC_ROUTE_OBJ_DIR)_periph/Vap_soc_periph_route_tb

clean:
	rm -rf $(AP_SOC_ROUTE_OBJ_DIR) file.list
