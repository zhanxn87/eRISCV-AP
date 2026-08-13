# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

PYTHON ?= python3

.PHONY: check-self-contained check-filelists core soc

check-self-contained:
	$(PYTHON) verification/check_self_contained.py

check-filelists:
	$(MAKE) -C dv/core/sim check-filelist
	$(MAKE) -C dv/soc/sim check-filelist

core: check-self-contained
	$(MAKE) -C dv/core/sim modelsim

soc: check-self-contained
	$(MAKE) -C dv/soc/sim modelsim
