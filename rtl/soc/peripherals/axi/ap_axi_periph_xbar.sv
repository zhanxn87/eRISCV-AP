// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

`include "axi/assign.svh"

// AP axi_periph AXI4 crossbar.
//
// The current configuration has one uncached hart manager, two targets (local
// APB and BPI NOR controller), and PULP axi_xbar's internal DECERR target.
// PULP axi_xbar owns AXI channel arbitration and response routing; this wrapper owns only the AP
// address map.  Adding hart managers expands the slave-side array here rather
// than adding another address router in a hart tile.
module ap_axi_periph_xbar
  import ap_soc_pkg::*;
(
  input logic clk_i,
  input logic rst_ni,

  AXI_BUS.Slave slv_axi_i,
  AXI_BUS.Master mst_axi_o [AP_AXI_PERIPH_EGRESS_PORTS-1:0]
);

  typedef struct packed {
    int unsigned idx;
    logic [AP_PADDR_W-1:0] start_addr;
    logic [AP_PADDR_W-1:0] end_addr;
  } xbar_rule_t;

  localparam axi_pkg::xbar_cfg_t XBAR_CFG = '{
    NoSlvPorts: AP_AXI_PERIPH_INGRESS_PORTS,
    NoMstPorts: AP_AXI_PERIPH_EGRESS_PORTS,
    MaxMstTrans: AP_AXI_PERIPH_MAX_OUTSTANDING,
    MaxSlvTrans: AP_AXI_PERIPH_MAX_OUTSTANDING,
    FallThrough: 1'b0,
    LatencyMode: axi_pkg::CUT_ALL_AX,
    AxiIdWidthSlvPorts: AP_AXI_SLV_ID_W,
    AxiIdUsedSlvPorts: AP_AXI_SLV_ID_W,
    UniqueIds: 1'b0,
    AxiAddrWidth: AP_PADDR_W,
    AxiDataWidth: AP_AXI_DATA_W,
    NoAddrRules: 4
  };

  localparam xbar_rule_t [XBAR_CFG.NoAddrRules-1:0] XBAR_RULES = '{
    '{idx: AP_AXI_PERIPH_EGRESS_APB,
      start_addr: AP_CLINT_BASE,
      end_addr: AP_CLINT_LIMIT},
    '{idx: AP_AXI_PERIPH_EGRESS_APB,
      start_addr: AP_PLIC_BASE,
      end_addr: AP_PLIC_LIMIT},
    '{idx: AP_AXI_PERIPH_EGRESS_APB,
      start_addr: AP_APB_BASE,
      end_addr: AP_APB_LIMIT},
    '{idx: AP_AXI_PERIPH_EGRESS_FLASH,
      start_addr: AP_BPI_BASE,
      end_addr: AP_BPI_LIMIT}
  };

  logic [AP_AXI_PERIPH_INGRESS_PORTS-1:0] xbar_default_enable;
  logic [AP_AXI_PERIPH_INGRESS_PORTS-1:0]
      [$clog2(AP_AXI_PERIPH_EGRESS_PORTS)-1:0] xbar_default_port;

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_PERIPH_MST_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) xbar_slv_axi [AP_AXI_PERIPH_INGRESS_PORTS-1:0] ();

  // Present the scalar public ingress as the one-element standard AXI array.
  `AXI_ASSIGN(xbar_slv_axi[0], slv_axi_i)

  assign xbar_default_enable = '0;
  assign xbar_default_port = '0;

  axi_xbar_intf #(
    .AXI_USER_WIDTH(AP_AXI_USER_W),
    .Cfg(XBAR_CFG),
    .rule_t(xbar_rule_t),
    .ATOPS(1'b0)
  ) xbar_i (
    .clk_i,
    .rst_ni,
    .test_i(1'b0),
    .slv_ports(xbar_slv_axi),
    .mst_ports(mst_axi_o),
    .addr_map_i(XBAR_RULES),
    .en_default_mst_port_i(xbar_default_enable),
    .default_mst_port_i(xbar_default_port)
  );

endmodule
