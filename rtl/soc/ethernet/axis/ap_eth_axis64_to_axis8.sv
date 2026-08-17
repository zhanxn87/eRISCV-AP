// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Narrow a contiguous-byte 64-bit AXI-stream beat to 8-bit stream transfers.
// A final partial beat uses the conventional low-contiguous TKEEP encoding.
module ap_eth_axis64_to_axis8 (
  input logic clk,
  input logic rst_n,
  input logic [63:0] s_axis_tdata_i,
  input logic [7:0] s_axis_tkeep_i,
  input logic s_axis_tvalid_i,
  output logic s_axis_tready_o,
  input logic s_axis_tlast_i,
  input logic s_axis_tuser_i,
  output logic [7:0] m_axis_tdata_o,
  output logic m_axis_tvalid_o,
  input logic m_axis_tready_i,
  output logic m_axis_tlast_o,
  output logic m_axis_tuser_o
);

  logic [63:0] data_q;
  logic [7:0] keep_q;
  logic last_q;
  logic user_q;
  logic valid_q;
  logic [2:0] byte_index_q;
  logic [2:0] last_index_q;
  integer lane;

  always_comb begin
    last_index_q = '0;
    for (lane = 0; lane < 8; lane = lane + 1)
      if (keep_q[lane])
        last_index_q = lane[2:0];
  end

  assign s_axis_tready_o = !valid_q;
  assign m_axis_tdata_o = data_q[byte_index_q * 8 +: 8];
  assign m_axis_tvalid_o = valid_q;
  assign m_axis_tlast_o = last_q && (byte_index_q == last_index_q);
  assign m_axis_tuser_o = user_q && m_axis_tlast_o;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      data_q <= '0;
      keep_q <= '0;
      last_q <= 1'b0;
      user_q <= 1'b0;
      valid_q <= 1'b0;
      byte_index_q <= '0;
    end else begin
      if (valid_q && m_axis_tready_i) begin
        if (byte_index_q == last_index_q)
          valid_q <= 1'b0;
        else
          byte_index_q <= byte_index_q + 1'b1;
      end
      if (s_axis_tvalid_i && s_axis_tready_o) begin
        data_q <= s_axis_tdata_i;
        keep_q <= s_axis_tkeep_i;
        last_q <= s_axis_tlast_i;
        user_q <= s_axis_tuser_i;
        valid_q <= |s_axis_tkeep_i;
        byte_index_q <= '0;
      end
    end
  end

endmodule
