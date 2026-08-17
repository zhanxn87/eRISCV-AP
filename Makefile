# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

PYTHON ?= python3

.PHONY: all check check-self-contained check-filelists hart-tile core soc

all: check

check: check-filelists hart-tile soc

check-self-contained:
	$(PYTHON) verification/check_self_contained.py

check-filelists:
	$(MAKE) -C dv/hart_tile/sim check-filelist
	$(MAKE) -C dv/soc/sim check-filelist

hart-tile: check-self-contained
	$(MAKE) -C dv/hart_tile/sim rv64-directed

# Compatibility alias; ap_hart_tile is the supported integration unit.
core: hart-tile

soc: check-self-contained
	$(MAKE) -C dv/soc/sim ap-soc-route
