# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

source [file join [file dirname [file normalize [info script]]] project_vcu108.tcl]
setup_vcu108_project

reset_run synth_1
reset_run impl_1
prepare_run_worker_environment
launch_runs impl_1 -to_step route_design
wait_on_run impl_1
open_run impl_1
report_route_status -file [file join $build_dir route_status.rpt]
report_utilization -file [file join $build_dir utilization_routed.rpt]
report_timing_summary -delay_type max -file [file join $build_dir timing_summary_routed.rpt]
report_clock_utilization -file [file join $build_dir clock_utilization_routed.rpt]
report_drc -file [file join $build_dir drc_routed.rpt]
report_methodology -file [file join $build_dir methodology_routed.rpt]
write_checkpoint -force [file join $build_dir ${top_name}_routed.dcp]
puts "INFO: M2 VCU108 implementation complete."
