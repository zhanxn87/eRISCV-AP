# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

if {![file exists work]} { vlib work }
vmap work work
vlog +acc -work work -incr -f file.list
vsim -lib work tcm_arbitration_tb
run -all
quit -f
