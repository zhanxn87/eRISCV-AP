# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause
# VCU108 M88E1111 SGMII PCS/PMA source configuration. Generated IP output is
# intentionally not tracked; instantiate it only from eriscv_ap_vcu108_top.


create_ip -name gig_ethernet_pcs_pma -vendor xilinx.com -library ip -module_name gig_ethernet_pcs_pma_0

set_property -dict [list \
    CONFIG.Standard {SGMII} \
    CONFIG.Physical_Interface {LVDS} \
    CONFIG.Management_Interface {false} \
    CONFIG.SupportLevel {Include_Shared_Logic_in_Core} \
    CONFIG.LvdsRefClk {625} \
] [get_ips gig_ethernet_pcs_pma_0]
