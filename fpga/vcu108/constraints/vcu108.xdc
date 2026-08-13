# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

# VCU108 board-level constraints. Pin data is from the Vivado VCU108 board file.
create_clock -period 3.333 -name sys_clk_300 [get_ports sys_clk_p]

set_property PACKAGE_PIN G31 [get_ports sys_clk_p]
set_property PACKAGE_PIN F31 [get_ports sys_clk_n]
set_property IOSTANDARD DIFF_SSTL12 [get_ports sys_clk_p]
set_property IOSTANDARD DIFF_SSTL12 [get_ports sys_clk_n]

set_property PACKAGE_PIN E36 [get_ports cpu_reset_i]
set_property IOSTANDARD LVCMOS12 [get_ports cpu_reset_i]

set_property PACKAGE_PIN BC24 [get_ports uart_rx_i]
set_property PACKAGE_PIN BE24 [get_ports uart_tx_o]
set_property IOSTANDARD LVCMOS18 [get_ports uart_rx_i]
set_property IOSTANDARD LVCMOS18 [get_ports uart_tx_o]

set_property PACKAGE_PIN BC40 [get_ports {boot_mode_i[0]}]
set_property PACKAGE_PIN L19 [get_ports {boot_mode_i[1]}]
set_property PACKAGE_PIN C37 [get_ports {boot_mode_i[2]}]
set_property IOSTANDARD LVCMOS12 [get_ports {boot_mode_i[*]}]

set_property PACKAGE_PIN AT32 [get_ports boot_uart_overrun_led_o]
set_property PACKAGE_PIN AV34 [get_ports boot_uart_protocol_error_led_o]
set_property IOSTANDARD LVCMOS12 [get_ports boot_uart_overrun_led_o]
set_property IOSTANDARD LVCMOS12 [get_ports boot_uart_protocol_error_led_o]

create_clock -period 100.000 -name jtag_tck [get_nets jtag_tck]

# The ungated SoC clock and its gated core derivative form synchronous paths
# through local memory. Apply the group directly to the BUFG/BUFGCE output
# segments so implementation balances their insertion delays.
set_property CLOCK_DELAY_GROUP ERISCV_SOC_CORE \
  [get_nets {soc_clk soc_i/core_clock_gate_i/core_clk}]

# Keep the fabric JTAG clock asynchronous to both the primary board clock and
# every MMCM-generated SoC clock derived from it.
set_clock_groups -asynchronous \
  -group [get_clocks -include_generated_clocks sys_clk_300] \
  -group [get_clocks jtag_tck]
set_false_path -from [get_ports cpu_reset_i]
set_false_path -from [get_ports {boot_mode_i[*]}]
