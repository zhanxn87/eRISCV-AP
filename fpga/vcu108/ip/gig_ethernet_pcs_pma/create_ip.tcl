# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause
# VCU108 M88E1111 SGMII PCS/PMA source configuration.

if {![info exists vcu108_ip_dir]} {
  set script_dir [file dirname [file normalize [info script]]]
  set vcu108_ip_dir [file normalize [file join $script_dir .. .. build ip]]
}
set ip_name gig_ethernet_pcs_pma_0
file mkdir $vcu108_ip_dir

if {[llength [get_ips -quiet $ip_name]] == 0} {
  create_ip -name gig_ethernet_pcs_pma -vendor xilinx.com -library ip \
    -module_name $ip_name -dir $vcu108_ip_dir
  set_property -dict [list \
    CONFIG.Standard {SGMII} \
    CONFIG.Physical_Interface {LVDS} \
    CONFIG.Management_Interface {false} \
    CONFIG.SupportLevel {Include_Shared_Logic_in_Core} \
    CONFIG.LvdsRefClk {625} \
  ] [get_ips $ip_name]
}

generate_target all [get_ips $ip_name]
