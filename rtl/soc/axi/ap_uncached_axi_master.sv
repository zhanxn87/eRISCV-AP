// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Blocking single-beat 64-bit AXI master for CPU device accesses. It owns no
// cache policy and accepts no atomics; dcache_cpu_router rejects uncached
// LR/SC and AMOs before they reach this block.
module ap_uncached_axi_master
  import ap_soc_pkg::*;
#(
  parameter logic [AP_AXI_SLV_ID_W-1:0] AXI_ID_P = 4'd1
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         cpu_req_i,
  input  logic [AP_PADDR_W-1:0]        cpu_addr_i,
  input  logic [63:0]                  cpu_wdata_i,
  input  logic                         cpu_we_i,
  input  logic [7:0]                   cpu_be_i,
  output logic                         cpu_resp_valid_o,
  output logic [63:0]                  cpu_rdata_o,
  output logic                         cpu_err_o,

  output logic [AP_AXI_SLV_ID_W-1:0]   m_axi_awid_o,
  output logic [AP_PADDR_W-1:0]        m_axi_awaddr_o,
  output logic [7:0]                   m_axi_awlen_o,
  output logic [2:0]                   m_axi_awsize_o,
  output logic [1:0]                   m_axi_awburst_o,
  output logic [3:0]                   m_axi_awcache_o,
  output logic                         m_axi_awvalid_o,
  input  logic                         m_axi_awready_i,

  output logic [63:0]                  m_axi_wdata_o,
  output logic [7:0]                   m_axi_wstrb_o,
  output logic                         m_axi_wlast_o,
  output logic                         m_axi_wvalid_o,
  input  logic                         m_axi_wready_i,

  input  logic [AP_AXI_SLV_ID_W-1:0]   m_axi_bid_i,
  input  logic [1:0]                   m_axi_bresp_i,
  input  logic                         m_axi_bvalid_i,
  output logic                         m_axi_bready_o,

  output logic [AP_AXI_SLV_ID_W-1:0]   m_axi_arid_o,
  output logic [AP_PADDR_W-1:0]        m_axi_araddr_o,
  output logic [7:0]                   m_axi_arlen_o,
  output logic [2:0]                   m_axi_arsize_o,
  output logic [1:0]                   m_axi_arburst_o,
  output logic [3:0]                   m_axi_arcache_o,
  output logic                         m_axi_arvalid_o,
  input  logic                         m_axi_arready_i,

  input  logic [AP_AXI_SLV_ID_W-1:0]   m_axi_rid_i,
  input  logic [63:0]                  m_axi_rdata_i,
  input  logic [1:0]                   m_axi_rresp_i,
  input  logic                         m_axi_rlast_i,
  input  logic                         m_axi_rvalid_i,
  output logic                         m_axi_rready_o
);

  localparam logic [1:0] AXI_BURST_INCR = 2'b01;
  localparam logic [1:0] AXI_RESP_OKAY = 2'b00;

  typedef enum logic [2:0] {
    UC_IDLE, UC_WRITE_ADDR, UC_WRITE_DATA, UC_WRITE_RESP,
    UC_READ_ADDR, UC_READ_DATA, UC_RESP
  } state_e;

  state_e state_q;
  logic [AP_PADDR_W-1:0] addr_q;
  logic [63:0] wdata_q, rdata_q;
  logic [7:0] be_q;
  logic err_q;

  always_comb begin
    m_axi_awid_o = AXI_ID_P;
    m_axi_awaddr_o = {addr_q[AP_PADDR_W-1:3], 3'b000};
    m_axi_awlen_o = 8'd0;
    m_axi_awsize_o = 3'd3;
    m_axi_awburst_o = AXI_BURST_INCR;
    m_axi_awcache_o = 4'b0000;
    m_axi_awvalid_o = state_q == UC_WRITE_ADDR;

    m_axi_wdata_o = wdata_q;
    m_axi_wstrb_o = be_q;
    m_axi_wlast_o = 1'b1;
    m_axi_wvalid_o = state_q == UC_WRITE_DATA;
    m_axi_bready_o = state_q == UC_WRITE_RESP;

    m_axi_arid_o = AXI_ID_P;
    m_axi_araddr_o = {addr_q[AP_PADDR_W-1:3], 3'b000};
    m_axi_arlen_o = 8'd0;
    m_axi_arsize_o = 3'd3;
    m_axi_arburst_o = AXI_BURST_INCR;
    m_axi_arcache_o = 4'b0000;
    m_axi_arvalid_o = state_q == UC_READ_ADDR;
    m_axi_rready_o = state_q == UC_READ_DATA;

    cpu_resp_valid_o = state_q == UC_RESP;
    cpu_rdata_o = rdata_q;
    cpu_err_o = err_q;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= UC_IDLE;
      addr_q <= '0;
      wdata_q <= '0;
      be_q <= '0;
      rdata_q <= '0;
      err_q <= 1'b0;
    end else begin
      unique case (state_q)
        UC_IDLE: begin
          if (cpu_req_i) begin
            addr_q <= cpu_addr_i;
            wdata_q <= cpu_wdata_i;
            be_q <= cpu_we_i ? cpu_be_i : 8'h00;
            err_q <= 1'b0;
            state_q <= cpu_we_i ? UC_WRITE_ADDR : UC_READ_ADDR;
          end
        end
        UC_WRITE_ADDR:
          if (m_axi_awready_i)
            state_q <= UC_WRITE_DATA;
        UC_WRITE_DATA:
          if (m_axi_wready_i)
            state_q <= UC_WRITE_RESP;
        UC_WRITE_RESP: begin
          if (m_axi_bvalid_i) begin
            err_q <= (m_axi_bid_i != AXI_ID_P) || (m_axi_bresp_i != AXI_RESP_OKAY);
            state_q <= UC_RESP;
          end
        end
        UC_READ_ADDR:
          if (m_axi_arready_i)
            state_q <= UC_READ_DATA;
        UC_READ_DATA: begin
          if (m_axi_rvalid_i) begin
            rdata_q <= m_axi_rdata_i;
            err_q <= (m_axi_rid_i != AXI_ID_P) ||
                     (m_axi_rresp_i != AXI_RESP_OKAY) || !m_axi_rlast_i;
            state_q <= UC_RESP;
          end
        end
        UC_RESP: state_q <= UC_IDLE;
        default: state_q <= UC_IDLE;
      endcase
    end
  end

endmodule
