// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// PHY-clock TX frame staging buffer. A root-clock DMA transfer first fills the
// asynchronous FIFO. A descriptor token then enables this block to capture the
// complete byte stream before presenting it to eth_mac_1g, so a PHY faster than
// the SoC root clock cannot underflow a frame. Completion is held until the
// MAC has accepted the frame's last byte.
module ap_eth_tx_frame_buffer #(
  parameter int unsigned MAX_FRAME_BYTES_P = 1536
) (
  input logic clk,
  input logic rst_n,

  input logic frame_start_i,
  input logic [7:0] s_axis_tdata_i,
  input logic s_axis_tvalid_i,
  output logic s_axis_tready_o,
  input logic s_axis_tlast_i,
  input logic s_axis_tuser_i,

  output logic [7:0] m_axis_tdata_o,
  output logic m_axis_tvalid_o,
  input logic m_axis_tready_i,
  output logic m_axis_tlast_o,
  output logic m_axis_tuser_o,

  output logic frame_complete_o
);

  localparam int unsigned ADDR_W = $clog2(MAX_FRAME_BYTES_P);

  logic [7:0] frame_mem [0:MAX_FRAME_BYTES_P-1];
  logic started_q;
  logic capture_q;
  logic stream_q;
  logic [15:0] wr_count_q;
  logic [15:0] frame_len_q;
  logic [15:0] rd_count_q;
  logic frame_error_q;

  assign s_axis_tready_o = capture_q;
  assign m_axis_tvalid_o = stream_q;
  assign m_axis_tdata_o = frame_mem[rd_count_q[ADDR_W-1:0]];
  assign m_axis_tlast_o = stream_q && ((rd_count_q + 16'd1) == frame_len_q);
  assign m_axis_tuser_o = frame_error_q && m_axis_tlast_o;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      started_q <= 1'b0;
      capture_q <= 1'b0;
      stream_q <= 1'b0;
      wr_count_q <= '0;
      frame_len_q <= '0;
      rd_count_q <= '0;
      frame_error_q <= 1'b0;
      frame_complete_o <= 1'b0;
    end else begin
      if (!frame_start_i) begin
        started_q <= 1'b0;
        frame_complete_o <= 1'b0;
      end else if (!started_q && !capture_q && !stream_q) begin
        started_q <= 1'b1;
        capture_q <= 1'b1;
        wr_count_q <= '0;
        frame_len_q <= '0;
        rd_count_q <= '0;
        frame_error_q <= 1'b0;
      end

      if (capture_q && s_axis_tvalid_i && s_axis_tready_o) begin
        if (wr_count_q < MAX_FRAME_BYTES_P) begin
          frame_mem[wr_count_q[ADDR_W-1:0]] <= s_axis_tdata_i;
          wr_count_q <= wr_count_q + 16'd1;
        end else begin
          frame_error_q <= 1'b1;
        end
        if (s_axis_tlast_i) begin
          capture_q <= 1'b0;
          frame_len_q <= wr_count_q + 16'd1;
          rd_count_q <= '0;
          stream_q <= 1'b1;
          if ((wr_count_q >= MAX_FRAME_BYTES_P) || s_axis_tuser_i)
            frame_error_q <= 1'b1;
        end
      end

      if (stream_q && m_axis_tready_i) begin
        if ((rd_count_q + 16'd1) == frame_len_q) begin
          stream_q <= 1'b0;
          frame_complete_o <= 1'b1;
        end else begin
          rd_count_q <= rd_count_q + 16'd1;
        end
      end
    end
  end

endmodule
