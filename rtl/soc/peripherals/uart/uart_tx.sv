// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

module uart_tx (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       baud_tick_i,
  input  logic       tx_enable_i,
  input  logic       start_i,
  input  logic [7:0] data_i,
  output logic       tx_o,
  output logic       busy_o,
  output logic       ready_o
);

  logic [9:0] shifter_q;
  logic [3:0] bit_count_q;

  assign busy_o  = bit_count_q != 4'd0;
  assign ready_o = tx_enable_i & !busy_o;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      shifter_q   <= 10'h3ff;
      bit_count_q <= 4'd0;
      tx_o        <= 1'b1;
    end else begin
      if (!tx_enable_i) begin
        shifter_q   <= 10'h3ff;
        bit_count_q <= 4'd0;
        tx_o        <= 1'b1;
      end else if (start_i && ready_o) begin
        shifter_q   <= {1'b1, data_i, 1'b0};
        bit_count_q <= 4'd10;
      end else if (baud_tick_i && busy_o) begin
        tx_o        <= shifter_q[0];
        shifter_q   <= {1'b1, shifter_q[9:1]};
        bit_count_q <= bit_count_q - 4'd1;
      end
    end
  end

endmodule
