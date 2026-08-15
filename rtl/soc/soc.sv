// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// eRISCV-AP top-level composition. SoC owns shared subsystem wiring only;
// hart-local translation/cache state lives in ap_hart_tile, cacheable traffic
// in ap_memory_system, and uncached traffic in ap_peripheral_subsystem.
import ap_soc_pkg::*;

module soc #(
  parameter int unsigned BOOT_ROM_SIZE_BYTES_P = 64 * 1024,
  parameter string BOOT_ROM_INIT_FILE_P = "",
  parameter bit ENABLE_BHT_P = 1'b1,
  parameter bit ENABLE_RAS_P = 1'b1,
  parameter bit ENABLE_UPPER_32_PREFETCH_P = 1'b1,
  parameter int unsigned MUL_ITER_BITS_P = 16
) (
  input logic clk,
  input logic rst_n,
  input logic fetch_enable_i,
  // Kept only for testbench compatibility. CLINT is the architectural time source.
  input logic [63:0] mtime_i,
  // Optional direct architectural interrupt injection for DV and board glue.
  input logic [31:0] irq_i,
  input logic uart_rx_i,
  output logic uart_tx_o,
  input logic [31:0] gpio_i,
  output logic [31:0] gpio_o,
  output logic [31:0] gpio_oe_o,
  input logic spi_miso_i,
  output logic spi_sclk_o,
  output logic spi_mosi_o,
  output logic [3:0] spi_ss_o,
  input logic debug_halt_req_i,
  input logic debug_resume_req_i,
  output logic debug_halted_o,
  output logic debug_running_o,
  output logic [63:0] debug_pc_o,
  output logic [2:0] debug_cause_o,
  AXI_BUS.Master ddr_axi_o,
  AXI_BUS.Master periph_axi_o
);

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) mem_axi [AP_AXI_INGRESS_PORTS-1:0] ();
  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) periph_axi ();

  logic eth_irq;
  logic clint_msip;
  logic clint_mtip;
  logic plic_meip;
  logic plic_seip;
  logic [63:0] clint_mtime;
  logic [31:0] hart_irq;

  always_comb begin
    hart_irq = irq_i;
    hart_irq[3] = irq_i[3] | clint_msip;
    hart_irq[7] = irq_i[7] | clint_mtip;
    hart_irq[9] = irq_i[9] | plic_seip;
    hart_irq[11] = irq_i[11] | plic_meip;
  end

  ap_cluster #(
    .BOOT_ROM_SIZE_BYTES_P(BOOT_ROM_SIZE_BYTES_P),
    .BOOT_ROM_INIT_FILE_P(BOOT_ROM_INIT_FILE_P),
    .ENABLE_BHT_P(ENABLE_BHT_P),
    .ENABLE_RAS_P(ENABLE_RAS_P),
    .ENABLE_UPPER_32_PREFETCH_P(ENABLE_UPPER_32_PREFETCH_P),
    .MUL_ITER_BITS_P(MUL_ITER_BITS_P)
  ) cluster_i (
    .clk,
    .rst_n,
    .fetch_enable_i,
    .mtime_i(clint_mtime),
    .irq_i(hart_irq),
    .debug_halt_req_i(debug_halt_req_i),
    .debug_resume_req_i(debug_resume_req_i),
    .debug_halted_o(debug_halted_o),
    .debug_running_o(debug_running_o),
    .debug_pc_o(debug_pc_o),
    .debug_cause_o(debug_cause_o),
    .mem_axi_o(mem_axi[1:0]),
    .periph_axi_o(periph_axi)
  );

  ap_ethernet_subsystem ethernet_i (
    .clk,
    .rst_n,
    .irq_o(eth_irq),
    .mem_axi_o(mem_axi[AP_AXI_INGRESS_ETH_DMA])
  );

  ap_memory_system memory_system_i (
    .clk,
    .rst_n,
    .mem_axi_i(mem_axi),
    .ddr_axi_o
  );

  ap_peripheral_subsystem peripheral_system_i (
    .clk(clk),
    .rst_n(rst_n),
    .eth_irq_i(eth_irq),
    .uart_rx_i(uart_rx_i),
    .uart_tx_o(uart_tx_o),
    .gpio_i(gpio_i),
    .gpio_o(gpio_o),
    .gpio_oe_o(gpio_oe_o),
    .spi_miso_i(spi_miso_i),
    .spi_sclk_o(spi_sclk_o),
    .spi_mosi_o(spi_mosi_o),
    .spi_ss_o(spi_ss_o),
    .mtime_o(clint_mtime),
    .msip_o(clint_msip),
    .mtip_o(clint_mtip),
    .meip_o(plic_meip),
    .seip_o(plic_seip),
    .periph_axi_i(periph_axi),
    .periph_axi_o(periph_axi_o)
  );

endmodule
