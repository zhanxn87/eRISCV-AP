// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Shared physical-memory subsystem. Its managers are I-Cache, D-Cache, and
// Ethernet DMA. It exposes DDR only; a local DECERR terminator catches any
// non-DDR request. Uncached MMIO is owned by ap_peripheral_subsystem.
// A future coherent L2/directory replaces this direct DDR-facing stage before
// ap_cluster may replicate private write-back D-Caches.
import ap_soc_pkg::*;

module ap_memory_system (
  input logic clk,
  input logic rst_n,
  AXI_BUS.Slave mem_axi_i [AP_AXI_INGRESS_PORTS-1:0],
  AXI_BUS.Master ddr_axi_o
);

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) fabric_egress [AP_AXI_EGRESS_PORTS-1:0] ();

  ap_axi64_fabric fabric_i (
    .clk_i(clk),
    .rst_ni(rst_n),
    .slv_axi_i(mem_axi_i),
    .mst_axi_o(fabric_egress)
  );

  ap_axi64_egress_bridge ddr_egress_i (
    .s_axi_i(fabric_egress[AP_AXI_EGRESS_DDR]),
    .m_axi_o(ddr_axi_o)
  );

  ap_axi64_error_slave addr_error_i (
    .clk,
    .rst_n,
    .s_axi_i(fabric_egress[AP_AXI_EGRESS_ERROR])
  );

endmodule
