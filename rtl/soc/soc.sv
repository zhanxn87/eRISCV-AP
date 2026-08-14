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
  input logic [63:0] mtime_i,
  input logic [31:0] irq_i,
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
  logic [31:0] hart_irq;
  assign hart_irq = irq_i | {31'b0, eth_irq};

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
    .mtime_i,
    .irq_i(hart_irq),
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
    .periph_axi_i(periph_axi),
    .periph_axi_o
  );

endmodule
