# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause
#
# Generate the VCU108 C1 DDR4 MIG IP.  The XCI is version controlled; every
# other generated file in ip/mig_ddr4_0/ is a Vivado build product.

set script_dir [file dirname [file normalize [info script]]]
set vcu108_dir [file normalize [file join $script_dir ..]]
set ip_name mig_ddr4_0
set ip_root [file normalize [file join $vcu108_dir ip]]
set ip_dir [file join $ip_root $ip_name]
set xci_file [file join $ip_dir $ip_name ${ip_name}.xci]
set part_name xcvu095-ffva2104-2-e
set board_part xilinx.com:vcu108:part0:1.7

# Do not import an existing XCI here. Vivado imports it into the active
# project and may synthesize a numbered sibling directory. Board builds own
# generated targets in their build directory; this source script owns only the
# reproducible XCI configuration.
if {[file exists $xci_file]} {
  puts "INFO: existing source XCI: $xci_file"
  exit
}

file mkdir $ip_root
create_project -in_memory -part $part_name
set_property board_part $board_part [current_project]
create_ip -name ddr4 -vendor xilinx.com -library ip \
  -module_name $ip_name -dir $ip_root
set mig_ip [get_ips $ip_name]

# The VCU108 C1 preset fixes the physical DDR4 topology and the resulting
# 512-bit AXI data path. AP's 64-bit memory fabric is adapted externally.
set_property CONFIG.C0_DDR4_BOARD_INTERFACE ddr4_sdram_c1_062 $mig_ip
set_property CONFIG.C0.DDR4_AxiSelection true $mig_ip
set_property CONFIG.C0.DDR4_AxiIDWidth 4 $mig_ip
# Keep the AP SoC in a low-frequency domain; DDR4 itself retains its 300 MHz UI.
set_property CONFIG.ADDN_UI_CLKOUT1_FREQ_HZ 50 $mig_ip
generate_target all $mig_ip
puts "INFO: created $xci_file"
exit
