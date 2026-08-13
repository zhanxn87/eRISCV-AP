# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

source [file join [file dirname [file normalize [info script]]] project_vcu108.tcl]
setup_vcu108_project

reset_run synth_1
prepare_run_worker_environment
launch_runs synth_1
wait_on_run synth_1
open_run synth_1
report_utilization -file [file join $build_dir utilization_synth.rpt]
report_timing_summary -delay_type max -file [file join $build_dir timing_summary_synth.rpt]
report_clock_utilization -file [file join $build_dir clock_utilization_synth.rpt]
write_checkpoint -force [file join $build_dir ${top_name}_synth.dcp]
puts "INFO: M2 VCU108 synthesis complete."
