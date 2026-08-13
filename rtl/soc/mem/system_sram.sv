// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Product-local shared System SRAM.  Reset does not initialize SRAM contents.
module system_sram #(
  parameter int ADDR_WIDTH = 17,
  parameter int DATA_WIDTH = 32,
  parameter int READ_LATENCY = 1
) (
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  req_valid_i,
  input  logic                  req_we_i,
  input  logic [3:0]            req_be_i,
  input  logic [ADDR_WIDTH-1:0] req_addr_i,
  input  logic [DATA_WIDTH-1:0] req_wdata_i,
  output logic                  resp_valid_o,
  output logic [DATA_WIDTH-1:0] resp_rdata_o,
  output logic                  resp_err_o
);

  logic [DATA_WIDTH-1:0] sram_rdata;
  logic [READ_LATENCY-1:0] resp_valid_pipe_q;
  integer index;

  sram_1rw #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) sram_i (
    .clk    (clk),
    .en_i   (req_valid_i),
    .we_i   (req_valid_i && req_we_i),
    .be_i   (req_be_i),
    .addr_i (req_addr_i),
    .wdata_i(req_wdata_i),
    .rdata_o(sram_rdata)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      resp_valid_pipe_q <= '0;
    else begin
      resp_valid_pipe_q[0] <= req_valid_i;
      for (index = 1; index < READ_LATENCY; index = index + 1)
        resp_valid_pipe_q[index] <= resp_valid_pipe_q[index-1];
    end
  end

  assign resp_valid_o = resp_valid_pipe_q[READ_LATENCY-1];
  assign resp_rdata_o = sram_rdata;
  assign resp_err_o = 1'b0;

endmodule
