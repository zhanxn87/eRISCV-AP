# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

if {![info exists tc]} { set tc MCU-C-01 }
if {![info exists testcase_dir]} { set testcase_dir ../../core/tests/C }
if {![info exists oracle_mode]} { set oracle_mode regs }
if {![info exists expected_regs_file]} { set expected_regs_file $testcase_dir/$tc.expected_regs }
if {![info exists instr_mem_file]} { set instr_mem_file $testcase_dir/$tc.mem }
if {![info exists data_mem_file]} { set data_mem_file "" }
if {![info exists boot_mode]} { set boot_mode bypass }
if {![info exists jtag_boot_trace_file]} { set jtag_boot_trace_file "" }
if {![info exists boot_addr]} { set boot_addr 10000000 }
if {![info exists irq_start_cycle]} { set irq_start_cycle 0 }
if {![info exists irq_duration]} { set irq_duration 0 }
if {![info exists plic_src_cycle]} { set plic_src_cycle 0 }
if {![info exists plic_src_id]} { set plic_src_id 0 }
if {![info exists plic_src_duration]} { set plic_src_duration 0 }
if {![info exists completion_reg]} { set completion_reg -1 }
if {![info exists completion_value]} { set completion_value 0 }
if {![info exists expected_uart_tx]} { set expected_uart_tx "" }
if {![info exists expected_uart_tx_bytes]} { set expected_uart_tx_bytes "" }
if {![info exists uart_rx_byte]} { set uart_rx_byte "" }
if {![info exists spi_miso_byte]} { set spi_miso_byte "" }
if {![info exists expected_spi_tx]} { set expected_spi_tx "" }
if {![info exists uart_baud_div]} { set uart_baud_div 8 }
if {![info exists uart_rx_start_cycle]} { set uart_rx_start_cycle 80 }
if {![info exists expected_bus_errors]} { set expected_bus_errors "" }
if {![info exists gpio_in]} { set gpio_in 0 }
if {![info exists expected_gpio_out]} { set expected_gpio_out "" }
if {![info exists expected_gpio_oe]} { set expected_gpio_oe "" }
if {![info exists max_cycles]} { set max_cycles 180 }
if {![info exists batch_mode]} { set batch_mode 0 }
if {![info exists enable_acc]} { set enable_acc [expr {!$batch_mode}] }
if {![info exists perf_profile]} { set perf_profile 0 }

if {![file exists work]} { vlib work }
vmap work work
if {$enable_acc} {
  vlog +acc -work work -incr -f file.list
} else {
  vlog -work work -incr -f file.list
}

set plusargs "+tc=$tc +instr_mem_file=$instr_mem_file +expected_regs_file=$expected_regs_file +boot_mode=$boot_mode +boot_addr=$boot_addr +max_cycles=$max_cycles +irq_start_cycle=$irq_start_cycle +irq_duration=$irq_duration +plic_src_cycle=$plic_src_cycle +plic_src_id=$plic_src_id +plic_src_duration=$plic_src_duration +uart_baud_div=$uart_baud_div +uart_rx_start_cycle=$uart_rx_start_cycle +gpio_in=$gpio_in"
if {$data_mem_file ne ""} { append plusargs " +data_mem_file=$data_mem_file" }
if {$jtag_boot_trace_file ne ""} { append plusargs " +jtag_boot_trace_file=$jtag_boot_trace_file" }
if {$expected_uart_tx ne ""} { append plusargs " +expected_uart_tx=$expected_uart_tx" }
if {$expected_uart_tx_bytes ne ""} { append plusargs " +expected_uart_tx_bytes=$expected_uart_tx_bytes" }
if {$uart_rx_byte ne ""} { append plusargs " +uart_rx_byte=$uart_rx_byte" }
if {$spi_miso_byte ne ""} { append plusargs " +spi_miso_byte=$spi_miso_byte" }
if {$expected_spi_tx ne ""} { append plusargs " +expected_spi_tx=$expected_spi_tx" }
if {$expected_bus_errors ne ""} { append plusargs " +expected_bus_errors=$expected_bus_errors" }
if {$expected_gpio_out ne ""} { append plusargs " +expected_gpio_out=$expected_gpio_out" }
if {$expected_gpio_oe ne ""} { append plusargs " +expected_gpio_oe=$expected_gpio_oe" }
if {$completion_reg >= 0} { append plusargs " +completion_reg=$completion_reg +completion_value=$completion_value" }
if {$perf_profile} { append plusargs " +perf_profile=1" }
eval vsim -lib work -t 1ps $plusargs soc_tb
run -all
if {$batch_mode} { quit -f }
