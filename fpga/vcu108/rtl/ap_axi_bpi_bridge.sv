// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Cross the AP BPI aperture into the VCU108 AXI EMC clock domain.  The AP
// address map remains 48-bit; AXI EMC sees a 32-bit, zero-based NOR aperture.
module ap_axi_bpi_bridge
  import ap_soc_pkg::*;
#(
  parameter int unsigned EMC_ADDR_W_P = 32,
  parameter int unsigned CDC_LOG_DEPTH_P = 2
) (
  input logic src_clk_i,
  input logic src_rst_ni,
  AXI_BUS.Slave ap_axi_i,

  input logic emc_clk_i,
  input logic emc_rst_ni,
  AXI_BUS.Master emc_axi_o
);

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) no_atop_axi ();
  AXI_BUS #(
    .AXI_ADDR_WIDTH(EMC_ADDR_W_P),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) local_axi ();
  logic [AP_PADDR_W-1:0] aw_offset;
  logic [AP_PADDR_W-1:0] ar_offset;
  logic [EMC_ADDR_W_P-1:0] emc_aw_addr;
  logic [EMC_ADDR_W_P-1:0] emc_ar_addr;

  assign aw_offset = no_atop_axi.aw_addr - AP_BPI_BASE;
  assign ar_offset = no_atop_axi.ar_addr - AP_BPI_BASE;
  assign emc_aw_addr = aw_offset[EMC_ADDR_W_P-1:0];
  assign emc_ar_addr = ar_offset[EMC_ADDR_W_P-1:0];

  axi_atop_filter_intf #(
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W),
    .AXI_MAX_WRITE_TXNS(AP_AXI_PERIPH_MAX_OUTSTANDING)
  ) atop_filter_i (
    .clk_i(src_clk_i),
    .rst_ni(src_rst_ni),
    .slv(ap_axi_i),
    .mst(no_atop_axi)
  );

  axi_modify_address_intf #(
    .AXI_SLV_PORT_ADDR_WIDTH(AP_PADDR_W),
    .AXI_MST_PORT_ADDR_WIDTH(EMC_ADDR_W_P),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) address_offset_i (
    .slv(no_atop_axi),
    .mst_aw_addr_i(emc_aw_addr),
    .mst_ar_addr_i(emc_ar_addr),
    .mst(local_axi)
  );

  axi_cdc_intf #(
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_ADDR_WIDTH(EMC_ADDR_W_P),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W),
    .LOG_DEPTH(CDC_LOG_DEPTH_P)
  ) bpi_cdc_i (
    .src_clk_i(src_clk_i),
    .src_rst_ni(src_rst_ni),
    .src(local_axi),
    .dst_clk_i(emc_clk_i),
    .dst_rst_ni(emc_rst_ni),
    .dst(emc_axi_o)
  );

endmodule
