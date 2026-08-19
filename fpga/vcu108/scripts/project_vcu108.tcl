# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

set script_dir [file dirname [file normalize [info script]]]
set vcu108_dir [file normalize [file join $script_dir ..]]
set ap_dir [file normalize [file join $vcu108_dir .. ..]]
if {[info exists ::env(ERISCV_VIVADO_BUILD_DIR)] && $::env(ERISCV_VIVADO_BUILD_DIR) ne ""} {
  set build_dir [file normalize $::env(ERISCV_VIVADO_BUILD_DIR)]
} else {
  set build_dir [file normalize [file join $vcu108_dir build]]
}
set part_name "xcvu095-ffva2104-2-e"
set board_part "xilinx.com:vcu108:part0:1.7"
set top_name "eriscv_ap_vcu108_top"
set project_name "eriscv_ap_vcu108"
set project_file [file join $build_dir ${project_name}.xpr]

proc append_filelist {filelist rtl_files_var include_dirs_var} {
  upvar 1 $rtl_files_var rtl_files
  upvar 1 $include_dirs_var include_dirs
  if {![file exists $filelist]} { error "Missing RTL file list: $filelist" }
  set fp [open $filelist r]
  while {[gets $fp raw_line] >= 0} {
    set line [string trim [string trimright $raw_line "\r"]]
    if {$line eq "" || [string match "//*" $line] || [string match "#*" $line]} { continue }
    if {[regexp {^-f\s+(.+)$} $line -> nested]} {
      append_filelist [file normalize [file join [file dirname $filelist] $nested]] rtl_files include_dirs
    } elseif {[string match "+incdir+*" $line]} {
      set include_dir [file normalize [file join [file dirname $filelist] [string range $line 8 end]]]
      if {![file isdirectory $include_dir]} { error "Missing include directory: $include_dir" }
      if {[lsearch -exact $include_dirs $include_dir] < 0} { lappend include_dirs $include_dir }
    } elseif {[string match "+*" $line] || [string match "-*" $line]} {
      error "Unsupported Vivado source-list option in $filelist: $line"
    } else {
      set rtl_file [file normalize [file join [file dirname $filelist] $line]]
      if {![file exists $rtl_file]} { error "Missing RTL file: $rtl_file" }
      if {[lsearch -exact $rtl_files $rtl_file] < 0} { lappend rtl_files $rtl_file }
    }
  }
  close $fp
}

proc source_file_present {source_files candidate} {
  set normalized_candidate [file normalize $candidate]
  foreach source_file $source_files {
    if {[string equal -nocase [file normalize $source_file] $normalized_candidate]} { return 1 }
  }
  return 0
}

proc copy_source_xci {source_xci build_dir} {
  set ip_name [file rootname [file tail $source_xci]]
  set target_xci [file join $build_dir ip $ip_name $ip_name.xci]
  file mkdir [file dirname $target_xci]
  if {![file exists $target_xci] || [file mtime $source_xci] > [file mtime $target_xci]} {
    file copy -force $source_xci $target_xci
  }
  return $target_xci
}

proc configure_run_strategies {} {
  set_property strategy Flow_AlternateRoutability [get_runs synth_1]
}

proc prepare_run_worker_environment {} {
  if {$::tcl_platform(platform) ne "windows" || ![info exists ::env(SystemRoot)]} { return }
  set system32 [file nativename [file join $::env(SystemRoot) System32]]
  set ::env(PATH) "${system32};$::env(PATH)"
  set ::env(PATHEXT) ".COM;.EXE;.BAT;.CMD"
}

proc setup_vcu108_project {} {
  global ap_dir board_part build_dir part_name project_file project_name top_name vcu108_dir
  set rtl_files [list]
  set include_dirs [list]
  append_filelist [file join $ap_dir rtl soc filelist.f] rtl_files include_dirs
  lappend rtl_files [file join $vcu108_dir rtl ap_axi_ddr_bridge.sv]
  lappend rtl_files [file join $vcu108_dir rtl ap_axi_bpi_bridge.sv]
  lappend rtl_files [file join $vcu108_dir rtl ap_vcu108_bpi_io.sv]
  lappend rtl_files [file join $vcu108_dir rtl ${top_name}.sv]

  set mig_xci [copy_source_xci [file join $vcu108_dir ip mig_ddr4_0 mig_ddr4_0 mig_ddr4_0.xci] $build_dir]
  set emc_xci [copy_source_xci [file join $vcu108_dir ip axi_emc_bpi axi_emc_bpi.xci] $build_dir]
  set xdc_file [file join $vcu108_dir constraints vcu108.xdc]

  if {[file exists $project_file]} {
    open_project $project_file
  } else {
    file mkdir $build_dir
    create_project $project_name $build_dir -part $part_name
    set_property target_language Verilog [current_project]
    set_property default_lib work [current_project]
  }
  set_property board_part $board_part [current_project]

  set source_files [get_files -quiet -of_objects [get_filesets sources_1]]
  foreach rtl_file $rtl_files {
    if {![source_file_present $source_files $rtl_file]} { add_files -fileset sources_1 -norecurse $rtl_file }
  }
  foreach ip_xci [list $mig_xci $emc_xci] {
    if {![source_file_present $source_files $ip_xci]} { add_files -fileset sources_1 -norecurse $ip_xci }
  }
  if {![source_file_present [get_files -quiet -of_objects [get_filesets constrs_1]] $xdc_file]} {
    add_files -fileset constrs_1 -norecurse $xdc_file
  }

  foreach ip_name [list mig_ddr4_0 axi_emc_bpi] {
    generate_target all [get_ips $ip_name]
  }
  set vcu108_ip_dir [file join $build_dir ip]
  source [file join $vcu108_dir ip gig_ethernet_pcs_pma create_ip.tcl]

  if {[llength $include_dirs] > 0} { set_property include_dirs $include_dirs [get_filesets sources_1] }
  set_property verilog_define {ERISCV_FPGA} [get_filesets sources_1]
  update_compile_order -fileset sources_1
  set_property top $top_name [get_filesets sources_1]
  configure_run_strategies
  puts "INFO: eRISCV-AP VCU108 project ready: $project_file"
}
