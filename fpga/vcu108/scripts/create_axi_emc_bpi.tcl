# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause
#
# Generate the VCU108 BPI NOR AXI EMC IP.  The XCI is version controlled;
# every other generated file in ip/axi_emc_bpi/ is a Vivado build product.

set script_dir [file dirname [file normalize [info script]]]
set vcu108_dir [file normalize [file join $script_dir ..]]
set ip_name axi_emc_bpi
if {[info exists ::env(ERISCV_VIVADO_IP_ROOT)] && $::env(ERISCV_VIVADO_IP_ROOT) ne ""} {
  set ip_root [file normalize $::env(ERISCV_VIVADO_IP_ROOT)]
} else {
  set ip_root [file normalize [file join $vcu108_dir ip]]
}
set ip_dir [file join $ip_root $ip_name]
set xci_file [file join $ip_dir ${ip_name}.xci]
set part_name xcvu095-ffva2104-2-e
set board_part xilinx.com:vcu108:part0:1.7

# Do not import an existing XCI.  Board builds own generated targets; this
# source script owns only the reproducible IP configuration.
if {[file exists $xci_file]} {
  puts "INFO: existing source XCI: $xci_file"
  exit
}

file mkdir $ip_root
create_project -in_memory -part $part_name
set_property board_part $board_part [current_project]
create_ip -name axi_emc -vendor xilinx.com -library ip \
  -module_name $ip_name -dir $ip_root
set emc_ip [get_ips $ip_name]

# VCU108 U58 is the x16, 128 MiB Micron MT28GU01GAAA1EGC-0SIT linear NOR.
# AXI uses a 32-bit local BPI aperture; `ap_axi_bpi_bridge` translates
# AP_BPI_BASE's 48-bit physical address to this 0x0000_0000 aperture.
# STARTUPE3 is external so that the wrapper owns the dedicated configuration
# pins and can provide the device-specific I/O/timing constraints.
set_property -dict [list \
  CONFIG.C_NUM_BANKS_MEM {1} \
  CONFIG.C_MEM0_TYPE {2} \
  CONFIG.C_MEM0_WIDTH {16} \
  CONFIG.C_MAX_MEM_WIDTH {16} \
  CONFIG.C_S_AXI_MEM_DATA_WIDTH {64} \
  CONFIG.C_S_AXI_MEM_ID_WIDTH {4} \
  CONFIG.C_S_AXI_MEM0_BASEADDR {0x00000000} \
  CONFIG.C_S_AXI_MEM0_HIGHADDR {0x07FFFFFF} \
  CONFIG.C_AXI_CLK_PERIOD_PS {10000} \
  CONFIG.C_TCEDV_PS_MEM_0 {96000} \
  CONFIG.C_TAVDV_PS_MEM_0 {96000} \
  CONFIG.C_TPACC_PS_FLASH_0 {15000} \
  CONFIG.C_THZCE_PS_MEM_0 {7000} \
  CONFIG.C_THZOE_PS_MEM_0 {7000} \
  CONFIG.C_TWC_PS_MEM_0 {40000} \
  CONFIG.C_TWP_PS_MEM_0 {40000} \
  CONFIG.C_TWPH_PS_MEM_0 {20000} \
  CONFIG.C_TLZWE_PS_MEM_0 {20000} \
  CONFIG.C_WR_REC_TIME_MEM_0 {200000} \
  CONFIG.C_USE_STARTUP {1} \
  CONFIG.C_USE_STARTUP_INT {0} \
] $emc_ip

generate_target all $emc_ip
puts "INFO: created $xci_file"
exit
