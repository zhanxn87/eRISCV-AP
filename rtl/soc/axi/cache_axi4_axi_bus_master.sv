// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Adapt the project-owned flattened cache AXI4 line adapter to the PULP AXI
// interface used by the AP central fabric. Cache requests do not issue ATOPs;
// RV64A operations are completed atomically by the blocking D-Cache.
module cache_axi4_axi_bus_master
  import ap_soc_pkg::*;
(
  input  logic [AP_AXI_SLV_ID_W-1:0]   axi_awid_i,
  input  logic [AP_PADDR_W-1:0]        axi_awaddr_i,
  input  logic [7:0]                   axi_awlen_i,
  input  logic [2:0]                   axi_awsize_i,
  input  logic [1:0]                   axi_awburst_i,
  input  logic [3:0]                   axi_awcache_i,
  input  logic                         axi_awvalid_i,
  output logic                         axi_awready_o,

  input  logic [AP_AXI_DATA_W-1:0]     axi_wdata_i,
  input  logic [AP_AXI_DATA_W/8-1:0]   axi_wstrb_i,
  input  logic                         axi_wlast_i,
  input  logic                         axi_wvalid_i,
  output logic                         axi_wready_o,

  output logic [AP_AXI_SLV_ID_W-1:0]   axi_bid_o,
  output logic [1:0]                   axi_bresp_o,
  output logic                         axi_bvalid_o,
  input  logic                         axi_bready_i,

  input  logic [AP_AXI_SLV_ID_W-1:0]   axi_arid_i,
  input  logic [AP_PADDR_W-1:0]        axi_araddr_i,
  input  logic [7:0]                   axi_arlen_i,
  input  logic [2:0]                   axi_arsize_i,
  input  logic [1:0]                   axi_arburst_i,
  input  logic [3:0]                   axi_arcache_i,
  input  logic                         axi_arvalid_i,
  output logic                         axi_arready_o,

  output logic [AP_AXI_SLV_ID_W-1:0]   axi_rid_o,
  output logic [AP_AXI_DATA_W-1:0]     axi_rdata_o,
  output logic [1:0]                   axi_rresp_o,
  output logic                         axi_rlast_o,
  output logic                         axi_rvalid_o,
  input  logic                         axi_rready_i,

  AXI_BUS.Master                        m_axi_o
);

  assign m_axi_o.aw_id = axi_awid_i;
  assign m_axi_o.aw_addr = axi_awaddr_i;
  assign m_axi_o.aw_len = axi_awlen_i;
  assign m_axi_o.aw_size = axi_awsize_i;
  assign m_axi_o.aw_burst = axi_awburst_i;
  assign m_axi_o.aw_lock = 1'b0;
  assign m_axi_o.aw_cache = axi_awcache_i;
  assign m_axi_o.aw_prot = '0;
  assign m_axi_o.aw_qos = '0;
  assign m_axi_o.aw_region = '0;
  assign m_axi_o.aw_atop = '0;
  assign m_axi_o.aw_user = '0;
  assign m_axi_o.aw_valid = axi_awvalid_i;
  assign axi_awready_o = m_axi_o.aw_ready;

  assign m_axi_o.w_data = axi_wdata_i;
  assign m_axi_o.w_strb = axi_wstrb_i;
  assign m_axi_o.w_last = axi_wlast_i;
  assign m_axi_o.w_user = '0;
  assign m_axi_o.w_valid = axi_wvalid_i;
  assign axi_wready_o = m_axi_o.w_ready;

  assign axi_bid_o = m_axi_o.b_id;
  assign axi_bresp_o = m_axi_o.b_resp;
  assign axi_bvalid_o = m_axi_o.b_valid;
  assign m_axi_o.b_ready = axi_bready_i;

  assign m_axi_o.ar_id = axi_arid_i;
  assign m_axi_o.ar_addr = axi_araddr_i;
  assign m_axi_o.ar_len = axi_arlen_i;
  assign m_axi_o.ar_size = axi_arsize_i;
  assign m_axi_o.ar_burst = axi_arburst_i;
  assign m_axi_o.ar_lock = 1'b0;
  assign m_axi_o.ar_cache = axi_arcache_i;
  assign m_axi_o.ar_prot = '0;
  assign m_axi_o.ar_qos = '0;
  assign m_axi_o.ar_region = '0;
  assign m_axi_o.ar_user = '0;
  assign m_axi_o.ar_valid = axi_arvalid_i;
  assign axi_arready_o = m_axi_o.ar_ready;

  assign axi_rid_o = m_axi_o.r_id;
  assign axi_rdata_o = m_axi_o.r_data;
  assign axi_rresp_o = m_axi_o.r_resp;
  assign axi_rlast_o = m_axi_o.r_last;
  assign axi_rvalid_o = m_axi_o.r_valid;
  assign m_axi_o.r_ready = axi_rready_i;

endmodule
