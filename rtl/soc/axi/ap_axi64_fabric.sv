// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// AP axi_mem AXI4 fabric.
//
// Three 4-bit-ID cacheable ingress ports (I-Cache, D-Cache, future Ethernet
// DMA) fan out to DDR and a local DECERR terminator. PULP axi_xbar prepends
// two route bits internally, producing 6-bit IDs. Each egress immediately
// maps no more than eight in-flight IDs back to the architectural 4-bit
// external boundary; a 6-bit ID never escapes this block.
module ap_axi64_fabric
  import ap_soc_pkg::*;
(
  input logic clk_i,
  input logic rst_ni,

  AXI_BUS.Slave  slv_axi_i [AP_AXI_INGRESS_PORTS-1:0],
  AXI_BUS.Master mst_axi_o [AP_AXI_EGRESS_PORTS-1:0]
);

  localparam axi_pkg::xbar_cfg_t XBAR_CFG = '{
    NoSlvPorts: AP_AXI_INGRESS_PORTS,
    NoMstPorts: AP_AXI_EGRESS_PORTS,
    MaxMstTrans: AP_AXI_MAX_OUTSTANDING,
    MaxSlvTrans: AP_AXI_MAX_OUTSTANDING,
    FallThrough: 1'b0,
    LatencyMode: axi_pkg::CUT_ALL_AX,
    AxiIdWidthSlvPorts: AP_AXI_SLV_ID_W,
    AxiIdUsedSlvPorts: AP_AXI_SLV_ID_W,
    UniqueIds: 1'b0,
    AxiAddrWidth: AP_PADDR_W,
    AxiDataWidth: AP_AXI_DATA_W,
    NoAddrRules: 2
  };

  localparam axi_pkg::xbar_rule_64_t [XBAR_CFG.NoAddrRules-1:0] XBAR_RULES = '{
    '{idx: AP_AXI_EGRESS_DDR,
      start_addr: {16'h0000, AP_DDR_BASE},
      end_addr: {16'h0000, AP_DDR_LIMIT}},
    '{idx: AP_AXI_EGRESS_ERROR,
      start_addr: 64'h0000_0000_0000_0000,
      end_addr: {16'h0000, AP_DDR_BASE}}
  };

  logic [AP_AXI_INGRESS_PORTS-1:0] xbar_default_enable;
  logic [AP_AXI_INGRESS_PORTS-1:0][$clog2(AP_AXI_EGRESS_PORTS)-1:0]
      xbar_default_port;

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_MST_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) xbar_mst_axi [AP_AXI_EGRESS_PORTS-1:0] ();

  assign xbar_default_enable = '0;
  assign xbar_default_port = '0;

  axi_xbar_intf #(
    .AXI_USER_WIDTH(AP_AXI_USER_W),
    .Cfg(XBAR_CFG),
    .ATOPS(1'b0)
  ) xbar_i (
    .clk_i,
    .rst_ni,
    .test_i(1'b0),
    .slv_ports(slv_axi_i),
    .mst_ports(xbar_mst_axi),
    .addr_map_i(XBAR_RULES),
    .en_default_mst_port_i(xbar_default_enable),
    .default_mst_port_i(xbar_default_port)
  );

  for (genvar port = 0; port < AP_AXI_EGRESS_PORTS; port++) begin : gen_id_width
    axi_iw_converter_intf #(
      .AXI_SLV_PORT_ID_WIDTH(AP_AXI_MST_ID_W),
      .AXI_MST_PORT_ID_WIDTH(AP_AXI_SLV_ID_W),
      .AXI_SLV_PORT_MAX_UNIQ_IDS(AP_AXI_MAX_OUTSTANDING),
      .AXI_SLV_PORT_MAX_TXNS_PER_ID(1),
      .AXI_SLV_PORT_MAX_TXNS(AP_AXI_MAX_OUTSTANDING),
      .AXI_MST_PORT_MAX_UNIQ_IDS(AP_AXI_MAX_OUTSTANDING),
      .AXI_MST_PORT_MAX_TXNS_PER_ID(1),
      .AXI_ADDR_WIDTH(AP_PADDR_W),
      .AXI_DATA_WIDTH(AP_AXI_DATA_W),
      .AXI_USER_WIDTH(AP_AXI_USER_W)
    ) id_width_i (
      .clk_i,
      .rst_ni,
      .slv(xbar_mst_axi[port]),
      .mst(mst_axi_o[port])
    );
  end

endmodule
