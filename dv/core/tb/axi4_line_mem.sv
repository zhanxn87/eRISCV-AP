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

  AXI_BUS.Slave s_axi_i
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
  logic read_error_q;
  logic read_error_enable_q;
  logic [PADDR_W_P-1:0] read_error_addr_q;
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
    read_error_enable_q = 1'b0;
    read_error_addr_q = '0;
    read_error_enable_q = $value$plusargs("axi_read_error_addr=%h", read_error_addr_q);
    if ((LINE_BITS_P % AXI_DATA_W_P) != 0)
      $fatal(1, "axi4_line_mem: line width must be an integer number of AXI beats");
  end

  assign s_axi_i.ar_ready = !read_active_q;
  assign s_axi_i.aw_ready = !write_active_q && !s_axi_i.b_valid;
  assign s_axi_i.w_ready = write_active_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      read_active_q <= 1'b0;
      read_error_q <= 1'b0;
      read_line_q <= '0;
      read_id_q <= '0;
      read_beat_q <= '0;
      write_active_q <= 1'b0;
      write_line_q <= '0;
      write_id_q <= '0;
      write_beat_q <= '0;
      write_error_q <= 1'b0;
      s_axi_i.r_id <= '0;
      s_axi_i.r_data <= '0;
      s_axi_i.r_resp <= AXI_RESP_OKAY;
      s_axi_i.r_last <= 1'b0;
      s_axi_i.r_user <= '0;
      s_axi_i.r_valid <= 1'b0;
      s_axi_i.b_id <= '0;
      s_axi_i.b_resp <= AXI_RESP_OKAY;
      s_axi_i.b_user <= '0;
      s_axi_i.b_valid <= 1'b0;
    end else begin
      if (s_axi_i.ar_valid && s_axi_i.ar_ready) begin
        read_active_q <= 1'b1;
        read_error_q <= read_error_enable_q &&
                        (s_axi_i.ar_addr == read_error_addr_q);
        read_line_q <= s_axi_i.ar_addr[OFFSET_W +: LINE_ADDR_W_P];
        read_id_q <= s_axi_i.ar_id;
        read_beat_q <= '0;
      end

      if (s_axi_i.r_valid && s_axi_i.r_ready) begin
        s_axi_i.r_valid <= 1'b0;
        if (s_axi_i.r_last)
          read_active_q <= 1'b0;
        else
          read_beat_q <= read_beat_q + 1'b1;
      end else if (read_active_q && !s_axi_i.r_valid) begin
        s_axi_i.r_id <= read_id_q;
        s_axi_i.r_data <= mem[read_line_q][read_beat_q * AXI_DATA_W_P +: AXI_DATA_W_P];
        s_axi_i.r_resp <= read_error_q ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
        s_axi_i.r_last <= read_beat_q == BEAT_W'(BEATS_P - 1);
        s_axi_i.r_valid <= 1'b1;
      end

      if (s_axi_i.aw_valid && s_axi_i.aw_ready) begin
        write_active_q <= 1'b1;
        write_line_q <= s_axi_i.aw_addr[OFFSET_W +: LINE_ADDR_W_P];
        write_id_q <= s_axi_i.aw_id;
        write_beat_q <= '0;
        write_error_q <= (s_axi_i.aw_len != 8'(BEATS_P - 1)) ||
                         (s_axi_i.aw_size != 3'($clog2(AXI_DATA_W_P / 8))) ||
                         (s_axi_i.aw_burst != 2'b01);
      end

      if (s_axi_i.w_valid && s_axi_i.w_ready) begin
        for (byte_lane = 0; byte_lane < AXI_DATA_W_P / 8; byte_lane = byte_lane + 1)
          if (s_axi_i.w_strb[byte_lane])
            mem[write_line_q][(write_beat_q * AXI_DATA_W_P) + byte_lane * 8 +: 8] <=
                s_axi_i.w_data[byte_lane * 8 +: 8];
        write_error_q <= write_error_q ||
                         (s_axi_i.w_last != (write_beat_q == BEAT_W'(BEATS_P - 1)));
        if (write_beat_q == BEAT_W'(BEATS_P - 1)) begin
          write_active_q <= 1'b0;
          s_axi_i.b_id <= write_id_q;
          s_axi_i.b_resp <= (write_error_q ||
                             (s_axi_i.w_last != (write_beat_q == BEAT_W'(BEATS_P - 1)))) ?
                            AXI_RESP_SLVERR : AXI_RESP_OKAY;
          s_axi_i.b_valid <= 1'b1;
        end else begin
          write_beat_q <= write_beat_q + 1'b1;
        end
      end

      if (s_axi_i.b_valid && s_axi_i.b_ready)
        s_axi_i.b_valid <= 1'b0;
    end
  end

endmodule
