# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

if {![info exists tc]} { set tc P1-ALU-01 }
if {![info exists testcase_dir]} { set testcase_dir ../tests/legacy/phase1 }
if {![info exists oracle_mode]} { set oracle_mode regs }
if {![info exists expected_regs_file] && $oracle_mode eq "regs"} { set expected_regs_file $testcase_dir/$tc.expected_regs }
if {![info exists reference_output_file] && $oracle_mode eq "signature"} { set reference_output_file $testcase_dir/$tc.reference_output }
if {![info exists instr_mem_file]} { set instr_mem_file $testcase_dir/$tc.mem }
if {![info exists data_mem_file]} { set data_mem_file "" }
if {![info exists sig_base]} { set sig_base 80 }
if {![info exists tohost_addr]} { set tohost_addr 0 }
if {![info exists tohost_pass_value]} { set tohost_pass_value 1 }
if {![info exists tohost_fail_value]} { set tohost_fail_value 3 }
if {![info exists boot_addr]} { set boot_addr 0 }
if {[info exists boot_mode] && $boot_mode ne "bypass"} {
  error "boot_mode is supported only by the SoC testbench"
}
if {![info exists irq_start_cycle]} { set irq_start_cycle 0 }
if {![info exists irq_duration]} { set irq_duration 0 }
if {![info exists irq_on_muldiv_busy]} { set irq_on_muldiv_busy 0 }
if {![info exists debug_halt_cycle]} { set debug_halt_cycle -1 }
if {![info exists debug_resume_cycle]} { set debug_resume_cycle -1 }
if {![info exists expected_debug_cause]} { set expected_debug_cause -1 }
if {![info exists reset_on_muldiv_busy]} { set reset_on_muldiv_busy 0 }
if {![info exists imem_read_latency]} { set imem_read_latency 1 }
if {![info exists dmem_read_latency]} { set dmem_read_latency 1 }
if {![info exists max_cycles]} { set max_cycles 180 }
if {![info exists batch_mode]} { set batch_mode 0 }
if {![info exists enable_acc]} { set enable_acc [expr {!$batch_mode}] }

if {![file exists work]} { vlib work }
vmap work work
if {$enable_acc} {
  vlog +acc -work work -incr -f file.list
} else {
  vlog -work work -incr -f file.list
}

set plusargs "+tc=$tc +instr_mem_file=$instr_mem_file +max_cycles=$max_cycles +boot_addr=$boot_addr +irq_start_cycle=$irq_start_cycle +irq_duration=$irq_duration +irq_on_muldiv_busy=$irq_on_muldiv_busy +debug_halt_cycle=$debug_halt_cycle +debug_resume_cycle=$debug_resume_cycle +expected_debug_cause=$expected_debug_cause +reset_on_muldiv_busy=$reset_on_muldiv_busy +oracle_mode=$oracle_mode"
if {$oracle_mode eq "regs"} {
  append plusargs " +expected_regs_file=$expected_regs_file"
} elseif {$oracle_mode eq "signature"} {
  append plusargs " +reference_output_file=$reference_output_file +sig_base=$sig_base +tohost_addr=$tohost_addr"
} elseif {$oracle_mode eq "act"} {
  append plusargs " +sig_base=$sig_base +tohost_addr=$tohost_addr +tohost_pass_value=$tohost_pass_value +tohost_fail_value=$tohost_fail_value"
} else {
  error "Unknown oracle_mode: $oracle_mode"
}
if {$data_mem_file ne ""} { append plusargs " +data_mem_file=$data_mem_file" }
eval vsim -lib work -t 1ps -gIMEM_READ_LATENCY=$imem_read_latency -gDMEM_READ_LATENCY=$dmem_read_latency $plusargs riscv_tb
run -all
if {$batch_mode} { quit -f }
