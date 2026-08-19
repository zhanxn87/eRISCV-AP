// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Byte-stream clock-domain crossing for the PHY/MAC and root-clock domains.
// The source must observe s_axis_tready_o.  eth_mac_1g RX has no backpressure,
// so a full RX FIFO drops bytes; software must provision receive buffers before
// enabling RX and hardware exposes this limitation as an RX overrun condition.
module ap_eth_axis8_cdc #(
  parameter int unsigned LOG_DEPTH_P = 11
) (
  input logic s_clk_i,
  input logic s_rst_ni,
  input logic [7:0] s_axis_tdata_i,
  input logic s_axis_tvalid_i,
  output logic s_axis_tready_o,
  input logic s_axis_tlast_i,
  input logic s_axis_tuser_i,
  input logic m_clk_i,
  input logic m_rst_ni,
  output logic [7:0] m_axis_tdata_o,
  output logic m_axis_tvalid_o,
  input logic m_axis_tready_i,
  output logic m_axis_tlast_o,
  output logic m_axis_tuser_o
);

  typedef logic [9:0] fifo_word_t;
  fifo_word_t s_word;
  fifo_word_t m_word;

  assign s_word = {s_axis_tlast_i, s_axis_tuser_i, s_axis_tdata_i};
  assign {m_axis_tlast_o, m_axis_tuser_o, m_axis_tdata_o} = m_word;

  cdc_fifo_gray #(
    .WIDTH(10),
    .T(fifo_word_t),
    .LOG_DEPTH(LOG_DEPTH_P)
  ) fifo_i (
    .src_rst_ni(s_rst_ni),
    .src_clk_i(s_clk_i),
    .src_data_i(s_word),
    .src_valid_i(s_axis_tvalid_i),
    .src_ready_o(s_axis_tready_o),
    .dst_rst_ni(m_rst_ni),
    .dst_clk_i(m_clk_i),
    .dst_data_o(m_word),
    .dst_valid_o(m_axis_tvalid_o),
    .dst_ready_i(m_axis_tready_i)
  );


endmodule
