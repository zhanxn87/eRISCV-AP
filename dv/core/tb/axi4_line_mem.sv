// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// Verification-only AXI4 memory slave for cache-line transactions.
//
// It supports one independent read and write burst at a time. Storage is
// intentionally exposed as cache lines so core testbenches can preload and
// inspect memory without bypassing the AXI transport under test.
module axi4_line_mem #(
  parameter int unsigned PADDR_W_P = 48,
  parameter int unsigned AXI_DATA_W_P = 64,
  parameter int unsigned AXI_ID_W_P = 4,
  parameter int unsigned LINE_BYTES_P = 64,
  parameter int unsigned LINE_ADDR_W_P = 10
) (
  input  logic clk,
  input  logic rst_n,

  input  logic [AXI_ID_W_P-1:0]        s_axi_awid_i,
  input  logic [PADDR_W_P-1:0]         s_axi_awaddr_i,
  input  logic [7:0]                   s_axi_awlen_i,
  input  logic [2:0]                   s_axi_awsize_i,
  input  logic [1:0]                   s_axi_awburst_i,
  input  logic [3:0]                   s_axi_awcache_i,
  input  logic                         s_axi_awvalid_i,
  output logic                         s_axi_awready_o,

  input  logic [AXI_DATA_W_P-1:0]      s_axi_wdata_i,
  input  logic [AXI_DATA_W_P/8-1:0]    s_axi_wstrb_i,
  input  logic                         s_axi_wlast_i,
  input  logic                         s_axi_wvalid_i,
  output logic                         s_axi_wready_o,

  output logic [AXI_ID_W_P-1:0]        s_axi_bid_o,
  output logic [1:0]                   s_axi_bresp_o,
  output logic                         s_axi_bvalid_o,
  input  logic                         s_axi_bready_i,

  input  logic [AXI_ID_W_P-1:0]        s_axi_arid_i,
  input  logic [PADDR_W_P-1:0]         s_axi_araddr_i,
  input  logic [7:0]                   s_axi_arlen_i,
  input  logic [2:0]                   s_axi_arsize_i,
  input  logic [1:0]                   s_axi_arburst_i,
  input  logic [3:0]                   s_axi_arcache_i,
  input  logic                         s_axi_arvalid_i,
  output logic                         s_axi_arready_o,

  output logic [AXI_ID_W_P-1:0]        s_axi_rid_o,
  output logic [AXI_DATA_W_P-1:0]      s_axi_rdata_o,
  output logic [1:0]                   s_axi_rresp_o,
  output logic                         s_axi_rlast_o,
  output logic                         s_axi_rvalid_o,
  input  logic                         s_axi_rready_i
);

  localparam int unsigned LINE_BITS_P = LINE_BYTES_P * 8;
  localparam int unsigned BEATS_P = LINE_BITS_P / AXI_DATA_W_P;
  localparam int unsigned BEAT_W = (BEATS_P > 1) ? $clog2(BEATS_P) : 1;
  localparam int unsigned OFFSET_W = $clog2(LINE_BYTES_P);
  localparam logic [1:0] AXI_RESP_OKAY = 2'b00;
  localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

  (* ram_style = "block", ramstyle = "no_rw_check" *)
  logic [LINE_BITS_P-1:0] mem [0:(1 << LINE_ADDR_W_P)-1];
  logic read_active_q;
  logic [LINE_ADDR_W_P-1:0] read_line_q;
  logic [AXI_ID_W_P-1:0] read_id_q;
  logic [BEAT_W-1:0] read_beat_q;
  logic write_active_q;
  logic [LINE_ADDR_W_P-1:0] write_line_q;
  logic [AXI_ID_W_P-1:0] write_id_q;
  logic [BEAT_W-1:0] write_beat_q;
  logic write_error_q;
  integer byte_lane;

  initial begin
    if ((LINE_BITS_P % AXI_DATA_W_P) != 0)
      $fatal(1, "axi4_line_mem: line width must be an integer number of AXI beats");
  end

  assign s_axi_arready_o = !read_active_q;
  assign s_axi_awready_o = !write_active_q && !s_axi_bvalid_o;
  assign s_axi_wready_o = write_active_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      read_active_q <= 1'b0;
      read_line_q <= '0;
      read_id_q <= '0;
      read_beat_q <= '0;
      write_active_q <= 1'b0;
      write_line_q <= '0;
      write_id_q <= '0;
      write_beat_q <= '0;
      write_error_q <= 1'b0;
      s_axi_rid_o <= '0;
      s_axi_rdata_o <= '0;
      s_axi_rresp_o <= AXI_RESP_OKAY;
      s_axi_rlast_o <= 1'b0;
      s_axi_rvalid_o <= 1'b0;
      s_axi_bid_o <= '0;
      s_axi_bresp_o <= AXI_RESP_OKAY;
      s_axi_bvalid_o <= 1'b0;
    end else begin
      if (s_axi_arvalid_i && s_axi_arready_o) begin
        read_active_q <= 1'b1;
        read_line_q <= s_axi_araddr_i[OFFSET_W +: LINE_ADDR_W_P];
        read_id_q <= s_axi_arid_i;
        read_beat_q <= '0;
      end

      if (s_axi_rvalid_o && s_axi_rready_i) begin
        s_axi_rvalid_o <= 1'b0;
        if (s_axi_rlast_o)
          read_active_q <= 1'b0;
        else
          read_beat_q <= read_beat_q + 1'b1;
      end else if (read_active_q && !s_axi_rvalid_o) begin
        s_axi_rid_o <= read_id_q;
        s_axi_rdata_o <= mem[read_line_q][read_beat_q * AXI_DATA_W_P +: AXI_DATA_W_P];
        s_axi_rresp_o <= AXI_RESP_OKAY;
        s_axi_rlast_o <= read_beat_q == BEAT_W'(BEATS_P - 1);
        s_axi_rvalid_o <= 1'b1;
      end

      if (s_axi_awvalid_i && s_axi_awready_o) begin
        write_active_q <= 1'b1;
        write_line_q <= s_axi_awaddr_i[OFFSET_W +: LINE_ADDR_W_P];
        write_id_q <= s_axi_awid_i;
        write_beat_q <= '0;
        write_error_q <= (s_axi_awlen_i != 8'(BEATS_P - 1)) ||
                         (s_axi_awsize_i != 3'($clog2(AXI_DATA_W_P / 8))) ||
                         (s_axi_awburst_i != 2'b01);
      end

      if (s_axi_wvalid_i && s_axi_wready_o) begin
        for (byte_lane = 0; byte_lane < AXI_DATA_W_P / 8; byte_lane = byte_lane + 1)
          if (s_axi_wstrb_i[byte_lane])
            mem[write_line_q][(write_beat_q * AXI_DATA_W_P) + byte_lane * 8 +: 8] <=
                s_axi_wdata_i[byte_lane * 8 +: 8];
        write_error_q <= write_error_q ||
                         (s_axi_wlast_i != (write_beat_q == BEAT_W'(BEATS_P - 1)));
        if (write_beat_q == BEAT_W'(BEATS_P - 1)) begin
          write_active_q <= 1'b0;
          s_axi_bid_o <= write_id_q;
          s_axi_bresp_o <= (write_error_q ||
                             (s_axi_wlast_i != (write_beat_q == BEAT_W'(BEATS_P - 1)))) ?
                            AXI_RESP_SLVERR : AXI_RESP_OKAY;
          s_axi_bvalid_o <= 1'b1;
        end else begin
          write_beat_q <= write_beat_q + 1'b1;
        end
      end

      if (s_axi_bvalid_o && s_axi_bready_i)
        s_axi_bvalid_o <= 1'b0;
    end
  end

endmodule
