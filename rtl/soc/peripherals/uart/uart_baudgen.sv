// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

module uart_baudgen (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        enable_i,
  input  logic [31:0] divisor_i,
  output logic        tick_o
);

  logic [31:0] count_q;
  logic [31:0] terminal_count;

  assign terminal_count = (divisor_i == 32'h0000_0000) ? 32'h0000_0000 : divisor_i - 32'h0000_0001;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      count_q <= 32'h0000_0000;
      tick_o  <= 1'b0;
    end else begin
      tick_o <= 1'b0;
      if (!enable_i) begin
        count_q <= 32'h0000_0000;
      end else if (count_q >= terminal_count) begin
        count_q <= 32'h0000_0000;
        tick_o  <= 1'b1;
      end else begin
        count_q <= count_q + 32'h0000_0001;
      end
    end
  end

endmodule
