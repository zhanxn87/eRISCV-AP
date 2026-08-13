# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

set script_dir [file dirname [file normalize [info script]]]
set vcu108_dir [file normalize [file join $script_dir ..]]
set mcu_dir [file normalize [file join $vcu108_dir .. ..]]
set build_dir [file normalize [file join $vcu108_dir build]]
set part_name "xcvu095-ffva2104-2-e"
set top_name "eriscv_m2_vcu108_wrapper"
set project_name "eriscv_m2_vcu108"
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
    if {[string equal -nocase [file normalize $source_file] $normalized_candidate]} {
      return 1
    }
  }
  return 0
}

proc configure_run_strategies {} {
  set_property strategy Flow_AlternateRoutability [get_runs synth_1]
  #set_property strategy Performance_NetDelay_high [get_runs impl_1]
}

# Vivado-generated runme.bat invokes a bare `cscript`.  Normalize the
# environment inherited by the run worker immediately before launch.
proc prepare_run_worker_environment {} {
  if {$::tcl_platform(platform) ne "windows" || ![info exists ::env(SystemRoot)]} { return }
  set system32 [file nativename [file join $::env(SystemRoot) System32]]
  set ::env(PATH) "${system32};$::env(PATH)"
  set ::env(PATHEXT) ".COM;.EXE;.BAT;.CMD"
}

proc setup_vcu108_project {} {
  global build_dir mcu_dir part_name project_file project_name top_name vcu108_dir
  set rtl_files [list]
  set include_dirs [list]
  append_filelist [file join $mcu_dir rtl soc filelist.f] rtl_files include_dirs
  lappend rtl_files [file join $vcu108_dir rtl ${top_name}.sv]

  if {[file exists $project_file]} {
    open_project $project_file
    # A persistent Vivado project does not automatically ingest new entries
    # from a repository filelist. Add missing files so RTL module additions do
    # not leave the existing project with a stale elaboration source set.
    set source_files [get_files -quiet -of_objects [get_filesets sources_1]]
    foreach rtl_file $rtl_files {
      if {![source_file_present $source_files $rtl_file]} {
        add_files -fileset sources_1 -norecurse $rtl_file
      }
    }
  } else {
    file mkdir $build_dir
    create_project $project_name $build_dir -part $part_name
    set_property target_language Verilog [current_project]
    set_property default_lib work [current_project]
    add_files -fileset sources_1 -norecurse {*}$rtl_files
    read_xdc [file join $vcu108_dir constraints vcu108.xdc]
  }
  if {[llength $include_dirs] > 0} {
    set_property include_dirs $include_dirs [get_filesets sources_1]
  }
  set_property verilog_define {ERISCV_FPGA} [get_filesets sources_1]
  update_compile_order -fileset sources_1
  # CVFPU vendor RTL contains independently elaboratable modules.  Reassert
  # the board wrapper for both a newly created and a persistent project so
  # Vivado never auto-selects a vendor leaf as the implementation top.
  set_property top $top_name [get_filesets sources_1]
  configure_run_strategies
  puts "INFO: M2 VCU108 project ready: $project_file"
}
