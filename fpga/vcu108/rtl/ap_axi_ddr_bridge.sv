// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Board-local DDR AXI adaptation.  The AP memory system is a 48-bit-address,
// 64-bit-data AXI4 master; the checked-in VCU108 MIG is a 31-bit-address,
// 512-bit-data AXI4 slave.  Atomic transactions are terminated here because
// the raw MIG AXI port does not implement AXI ATOP.
module ap_axi_ddr_bridge
  import ap_soc_pkg::*;
#(
  parameter int unsigned MIG_ADDR_W_P = 31,
  parameter int unsigned MIG_DATA_W_P = 512,
  parameter int unsigned MAX_READS_P = 8,
  parameter int unsigned MAX_WRITES_P = 8
) (
  input logic clk_i,
  input logic rst_ni,

  AXI_BUS.Slave ap_axi_i,
  AXI_BUS.Master mig_axi_o
);

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) no_atop_axi ();
  AXI_BUS #(
    .AXI_ADDR_WIDTH(MIG_ADDR_W_P),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) local_axi ();

  logic [AP_PADDR_W-1:0] aw_offset;
  logic [AP_PADDR_W-1:0] ar_offset;
  logic [MIG_ADDR_W_P-1:0] mig_aw_addr;
  logic [MIG_ADDR_W_P-1:0] mig_ar_addr;

  assign aw_offset = no_atop_axi.aw_addr - AP_DDR_BASE;
  assign ar_offset = no_atop_axi.ar_addr - AP_DDR_BASE;
  assign mig_aw_addr = aw_offset[MIG_ADDR_W_P-1:0];
  assign mig_ar_addr = ar_offset[MIG_ADDR_W_P-1:0];

  axi_atop_filter_intf #(
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W),
    .AXI_MAX_WRITE_TXNS(MAX_WRITES_P)
  ) atop_filter_i (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .slv(ap_axi_i),
    .mst(no_atop_axi)
  );

  axi_modify_address_intf #(
    .AXI_SLV_PORT_ADDR_WIDTH(AP_PADDR_W),
    .AXI_MST_PORT_ADDR_WIDTH(MIG_ADDR_W_P),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) address_offset_i (
    .slv(no_atop_axi),
    .mst_aw_addr_i(mig_aw_addr),
    .mst_ar_addr_i(mig_ar_addr),
    .mst(local_axi)
  );

  axi_dw_converter_intf #(
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_ADDR_WIDTH(MIG_ADDR_W_P),
    .AXI_SLV_PORT_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_MST_PORT_DATA_WIDTH(MIG_DATA_W_P),
    .AXI_USER_WIDTH(AP_AXI_USER_W),
    .AXI_MAX_READS(MAX_READS_P)
  ) data_width_i (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .slv(local_axi),
    .mst(mig_axi_o)
  );

  initial begin
    if (MIG_ADDR_W_P > AP_PADDR_W)
      $fatal(1, "ap_axi_ddr_bridge: MIG address width exceeds AP physical address width");
    if (MIG_DATA_W_P != 512)
      $fatal(1, "ap_axi_ddr_bridge: the checked-in VCU108 MIG requires a 512-bit AXI port");
  end

endmodule
