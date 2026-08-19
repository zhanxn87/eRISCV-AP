// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// One descriptor-backed RX frame staging buffer. The ring engine arms it for
// each hardware-owned descriptor; it records a complete MAC frame before the
// DDR write DMA, which gives axi_dma its required transfer length.
module ap_eth_rx_frame_buffer #(
  parameter int unsigned MAX_FRAME_BYTES_P = 2048
) (
  input logic clk,
  input logic rst_n,

  input logic arm_i,
  input logic [15:0] capacity_i,
  input logic rx_enable_i,

  input logic [7:0] s_axis_tdata_i,
  input logic s_axis_tvalid_i,
  output logic s_axis_tready_o,
  input logic s_axis_tlast_i,
  input logic s_axis_tuser_i,

  output logic frame_ready_o,
  output logic [15:0] frame_len_o,
  output logic frame_drop_o,

  input logic stream_start_i,
  output logic [63:0] m_axis_tdata_o,
  output logic [7:0] m_axis_tkeep_o,
  output logic m_axis_tvalid_o,
  input logic m_axis_tready_i,
  output logic m_axis_tlast_o,
  input logic release_i
);

  localparam int unsigned ADDR_W = $clog2(MAX_FRAME_BYTES_P);
  logic [7:0] frame_mem [0:MAX_FRAME_BYTES_P-1];
  logic armed_q;
  logic capture_q;
  logic drop_q;
  logic [15:0] capacity_q;
  logic [15:0] wr_count_q;
  logic frame_ready_q;
  logic [15:0] frame_len_q;
  logic stream_active_q;
  logic [15:0] rd_count_q;
  integer lane;

  assign s_axis_tready_o = 1'b1;
  assign frame_ready_o = frame_ready_q;
  assign frame_len_o = frame_len_q;
  assign m_axis_tvalid_o = stream_active_q;
  assign m_axis_tlast_o = stream_active_q &&
                          ((rd_count_q + 16'd8) >= frame_len_q);

  always_comb begin
    m_axis_tdata_o = '0;
    m_axis_tkeep_o = '0;
    for (lane = 0; lane < 8; lane = lane + 1) begin
      if ((rd_count_q + lane) < frame_len_q) begin
        m_axis_tdata_o[lane * 8 +: 8] = frame_mem[rd_count_q + lane];
        m_axis_tkeep_o[lane] = 1'b1;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      armed_q <= 1'b0;
      capture_q <= 1'b0;
      drop_q <= 1'b0;
      capacity_q <= '0;
      wr_count_q <= '0;
      frame_ready_q <= 1'b0;
      frame_len_q <= '0;
      stream_active_q <= 1'b0;
      rd_count_q <= '0;
      frame_drop_o <= 1'b0;
    end else begin
      frame_drop_o <= 1'b0;

      if (arm_i && !armed_q && !capture_q && !frame_ready_q && !stream_active_q) begin
        armed_q <= 1'b1;
        capacity_q <= capacity_i;
        wr_count_q <= '0;
        drop_q <= 1'b0;
      end

      if (s_axis_tvalid_i && rx_enable_i) begin
        if (armed_q && !capture_q && !frame_ready_q && !stream_active_q) begin
          if ((capacity_q != 0) && (capacity_q <= MAX_FRAME_BYTES_P)) begin
            frame_mem[0] <= s_axis_tdata_i;
            wr_count_q <= 16'd1;
          end else begin
            drop_q <= 1'b1;
          end
          if (s_axis_tlast_i) begin
            armed_q <= 1'b0;
            if (!s_axis_tuser_i && (capacity_q != 0) &&
                (capacity_q <= MAX_FRAME_BYTES_P)) begin
              frame_len_q <= 16'd1;
              frame_ready_q <= 1'b1;
            end else begin
              frame_drop_o <= 1'b1;
            end
          end else begin
            capture_q <= 1'b1;
          end
        end else if (capture_q) begin
          if ((wr_count_q < capacity_q) && (wr_count_q < MAX_FRAME_BYTES_P)) begin
            frame_mem[wr_count_q[ADDR_W-1:0]] <= s_axis_tdata_i;
            wr_count_q <= wr_count_q + 1'b1;
          end else begin
            drop_q <= 1'b1;
          end
          if (s_axis_tlast_i) begin
            capture_q <= 1'b0;
            armed_q <= 1'b0;
            if (!drop_q && !s_axis_tuser_i &&
                (wr_count_q < capacity_q) && (wr_count_q < MAX_FRAME_BYTES_P)) begin
              frame_len_q <= wr_count_q + 1'b1;
              frame_ready_q <= 1'b1;
            end else begin
              frame_drop_o <= 1'b1;
            end
          end
        end
      end

      if (stream_start_i && frame_ready_q && !stream_active_q) begin
        stream_active_q <= 1'b1;
        rd_count_q <= '0;
      end

      if (stream_active_q && m_axis_tready_i) begin
        if ((rd_count_q + 16'd8) >= frame_len_q)
          stream_active_q <= 1'b0;
        else
          rd_count_q <= rd_count_q + 16'd8;
      end

      if (release_i) begin
        frame_ready_q <= 1'b0;
        frame_len_q <= '0;
        stream_active_q <= 1'b0;
        rd_count_q <= '0;
      end

      if (!rx_enable_i && !stream_active_q) begin
        armed_q <= 1'b0;
        capture_q <= 1'b0;
        drop_q <= 1'b0;
        frame_ready_q <= 1'b0;
        frame_len_q <= '0;
        rd_count_q <= '0;
      end
    end
  end

endmodule
