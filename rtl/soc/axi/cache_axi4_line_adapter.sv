// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// Blocking full-cache-line to AXI4 adapter.
//
// The cache-side contract permits one line operation at a time. Reads and
// writes are converted to one INCR burst of LINE_BYTES_P bytes. This module
// has no policy knowledge: cacheability/MMIO routing remains above it.
module cache_axi4_line_adapter #(
  parameter int unsigned PADDR_W_P     = 48,
  parameter int unsigned AXI_DATA_W_P  = 64,
  parameter int unsigned AXI_ID_W_P    = 4,
  parameter int unsigned LINE_BYTES_P  = 64,
  parameter logic [AXI_ID_W_P-1:0] AXI_ID_P = '0
) (
  input  logic clk,
  input  logic rst_n,

  // One outstanding line operation maximum.
  input  logic                         line_req_i,
  input  logic                         line_we_i,
  input  logic [PADDR_W_P-1:0]         line_addr_i,
  input  logic [LINE_BYTES_P*8-1:0]    line_wdata_i,
  output logic                         line_resp_valid_o,
  output logic [LINE_BYTES_P*8-1:0]    line_rdata_o,
  output logic                         line_err_o,

  output logic [AXI_ID_W_P-1:0]        m_axi_awid_o,
  output logic [PADDR_W_P-1:0]         m_axi_awaddr_o,
  output logic [7:0]                   m_axi_awlen_o,
  output logic [2:0]                   m_axi_awsize_o,
  output logic [1:0]                   m_axi_awburst_o,
  output logic [3:0]                   m_axi_awcache_o,
  output logic                         m_axi_awvalid_o,
  input  logic                         m_axi_awready_i,

  output logic [AXI_DATA_W_P-1:0]      m_axi_wdata_o,
  output logic [AXI_DATA_W_P/8-1:0]    m_axi_wstrb_o,
  output logic                         m_axi_wlast_o,
  output logic                         m_axi_wvalid_o,
  input  logic                         m_axi_wready_i,

  input  logic [AXI_ID_W_P-1:0]        m_axi_bid_i,
  input  logic [1:0]                   m_axi_bresp_i,
  input  logic                         m_axi_bvalid_i,
  output logic                         m_axi_bready_o,

  output logic [AXI_ID_W_P-1:0]        m_axi_arid_o,
  output logic [PADDR_W_P-1:0]         m_axi_araddr_o,
  output logic [7:0]                   m_axi_arlen_o,
  output logic [2:0]                   m_axi_arsize_o,
  output logic [1:0]                   m_axi_arburst_o,
  output logic [3:0]                   m_axi_arcache_o,
  output logic                         m_axi_arvalid_o,
  input  logic                         m_axi_arready_i,

  input  logic [AXI_ID_W_P-1:0]        m_axi_rid_i,
  input  logic [AXI_DATA_W_P-1:0]      m_axi_rdata_i,
  input  logic [1:0]                   m_axi_rresp_i,
  input  logic                         m_axi_rlast_i,
  input  logic                         m_axi_rvalid_i,
  output logic                         m_axi_rready_o
);

  localparam int unsigned LINE_BITS_P = LINE_BYTES_P * 8;
  localparam int unsigned BEATS_P = LINE_BITS_P / AXI_DATA_W_P;
  localparam int unsigned BEAT_W = (BEATS_P > 1) ? $clog2(BEATS_P) : 1;
  localparam int unsigned LINE_OFFSET_W = $clog2(LINE_BYTES_P);
  localparam int unsigned AXI_SIZE_P = $clog2(AXI_DATA_W_P / 8);
  localparam logic [1:0] AXI_RESP_OKAY = 2'b00;
  localparam logic [1:0] AXI_BURST_INCR = 2'b01;

  typedef enum logic [2:0] {
    AXI_IDLE,
    AXI_READ_ADDR,
    AXI_READ_DATA,
    AXI_WRITE_ADDR,
    AXI_WRITE_DATA,
    AXI_WRITE_RESP,
    AXI_RESP
  } state_e;

  state_e state_q;
  logic [PADDR_W_P-1:0] line_addr_q;
  logic [LINE_BITS_P-1:0] line_wdata_q;
  logic [LINE_BITS_P-1:0] line_rdata_q;
  logic [BEAT_W-1:0] beat_q;
  logic line_err_q;

  initial begin
    if ((LINE_BITS_P % AXI_DATA_W_P) != 0)
      $fatal(1, "cache_axi4_line_adapter: line width must be an integer number of AXI beats");
    if (BEATS_P > 256)
      $fatal(1, "cache_axi4_line_adapter: AXI LEN cannot encode this line size");
  end

  always_comb begin
    m_axi_awid_o = AXI_ID_P;
    m_axi_awaddr_o = {line_addr_q[PADDR_W_P-1:LINE_OFFSET_W], {LINE_OFFSET_W{1'b0}}};
    m_axi_awlen_o = 8'(BEATS_P - 1);
    m_axi_awsize_o = 3'(AXI_SIZE_P);
    m_axi_awburst_o = AXI_BURST_INCR;
    m_axi_awcache_o = 4'b1111;
    m_axi_awvalid_o = 1'b0;

    m_axi_wdata_o = line_wdata_q[beat_q * AXI_DATA_W_P +: AXI_DATA_W_P];
    m_axi_wstrb_o = {AXI_DATA_W_P / 8{1'b1}};
    m_axi_wlast_o = beat_q == BEAT_W'(BEATS_P - 1);
    m_axi_wvalid_o = 1'b0;
    m_axi_bready_o = 1'b0;

    m_axi_arid_o = AXI_ID_P;
    m_axi_araddr_o = {line_addr_q[PADDR_W_P-1:LINE_OFFSET_W], {LINE_OFFSET_W{1'b0}}};
    m_axi_arlen_o = 8'(BEATS_P - 1);
    m_axi_arsize_o = 3'(AXI_SIZE_P);
    m_axi_arburst_o = AXI_BURST_INCR;
    m_axi_arcache_o = 4'b1111;
    m_axi_arvalid_o = 1'b0;
    m_axi_rready_o = 1'b0;

    line_resp_valid_o = state_q == AXI_RESP;
    line_rdata_o = line_rdata_q;
    line_err_o = line_err_q;

    unique case (state_q)
      AXI_READ_ADDR:  m_axi_arvalid_o = 1'b1;
      AXI_READ_DATA:  m_axi_rready_o = 1'b1;
      AXI_WRITE_ADDR: m_axi_awvalid_o = 1'b1;
      AXI_WRITE_DATA: m_axi_wvalid_o = 1'b1;
      AXI_WRITE_RESP: m_axi_bready_o = 1'b1;
      default: ;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= AXI_IDLE;
      line_addr_q <= '0;
      line_wdata_q <= '0;
      line_rdata_q <= '0;
      beat_q <= '0;
      line_err_q <= 1'b0;
    end else begin
      unique case (state_q)
        AXI_IDLE: begin
          if (line_req_i) begin
            line_addr_q <= line_addr_i;
            line_wdata_q <= line_wdata_i;
            line_rdata_q <= '0;
            line_err_q <= 1'b0;
            beat_q <= '0;
            state_q <= line_we_i ? AXI_WRITE_ADDR : AXI_READ_ADDR;
          end
        end

        AXI_READ_ADDR: begin
          if (m_axi_arready_i)
            state_q <= AXI_READ_DATA;
        end

        AXI_READ_DATA: begin
          if (m_axi_rvalid_i) begin
            line_rdata_q[beat_q * AXI_DATA_W_P +: AXI_DATA_W_P] <= m_axi_rdata_i;
            if (m_axi_rlast_i || (beat_q == BEAT_W'(BEATS_P - 1))) begin
              line_err_q <= line_err_q ||
                            (m_axi_rid_i != AXI_ID_P) ||
                            (m_axi_rresp_i != AXI_RESP_OKAY) ||
                            !m_axi_rlast_i ||
                            (beat_q != BEAT_W'(BEATS_P - 1));
              state_q <= AXI_RESP;
            end else begin
              line_err_q <= line_err_q ||
                            (m_axi_rid_i != AXI_ID_P) ||
                            (m_axi_rresp_i != AXI_RESP_OKAY);
              beat_q <= beat_q + 1'b1;
            end
          end
        end

        AXI_WRITE_ADDR: begin
          if (m_axi_awready_i)
            state_q <= AXI_WRITE_DATA;
        end

        AXI_WRITE_DATA: begin
          if (m_axi_wready_i) begin
            if (beat_q == BEAT_W'(BEATS_P - 1))
              state_q <= AXI_WRITE_RESP;
            else
              beat_q <= beat_q + 1'b1;
          end
        end

        AXI_WRITE_RESP: begin
          if (m_axi_bvalid_i) begin
            line_err_q <= (m_axi_bid_i != AXI_ID_P) ||
                          (m_axi_bresp_i != AXI_RESP_OKAY);
            state_q <= AXI_RESP;
          end
        end

        AXI_RESP: state_q <= AXI_IDLE;
        default: state_q <= AXI_IDLE;
      endcase
    end
  end

endmodule
