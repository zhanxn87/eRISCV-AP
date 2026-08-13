// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// DBus adapter for the portable single-port data SRAM.
module data_mem #(
  parameter ADDR_WIDTH = 13,
  parameter DATA_WIDTH = 32,
  parameter BYTE_LANES = DATA_WIDTH / 8,
  parameter READ_LATENCY = 1
) (
  // Clock and reset
  input  logic                  clk,
  input  logic                  rst_n,

  // Single-port SRAM request/response transaction
  input  logic                  req_i,
  input  logic                  we_i,
  input  logic [BYTE_LANES-1:0] be_i,
  input  logic [ADDR_WIDTH-1:0] addr_i,
  input  logic [DATA_WIDTH-1:0] wdata_i,
  output logic                  resp_valid_o,
  output logic                  resp_write_o,
  output logic [DATA_WIDTH-1:0] rdata_o,
  output logic                  err_o
);

  // SRAM response and registered completion pipeline
  logic sram_resp_valid;
  logic [DATA_WIDTH-1:0] sram_rdata;
  logic [READ_LATENCY-1:0] resp_valid_pipe_q;
  logic [READ_LATENCY-1:0] resp_write_pipe_q;
  integer index;

  sram_1rw #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) sram_i (
    .clk    (clk),
    .en_i   (req_i),
    .we_i   (req_i && we_i),
    .be_i   (be_i),
    .addr_i (addr_i),
    .wdata_i(wdata_i),
    .rdata_o(sram_rdata)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      resp_valid_pipe_q <= '0;
      resp_write_pipe_q <= '0;
    end else begin
      resp_valid_pipe_q[0] <= req_i;
      resp_write_pipe_q[0] <= req_i && we_i;
      for (index = 1; index < READ_LATENCY; index = index + 1) begin
        resp_valid_pipe_q[index] <= resp_valid_pipe_q[index-1];
        resp_write_pipe_q[index] <= resp_write_pipe_q[index-1];
      end
    end
  end

  generate
    if (READ_LATENCY == 1) begin : gen_one_cycle_read
      assign rdata_o = sram_rdata;
    end else begin : gen_extra_read_latency
      logic [DATA_WIDTH-1:0] rdata_pipe_q [0:READ_LATENCY-2];
      integer pipe_index;

      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          for (pipe_index = 0; pipe_index < READ_LATENCY-1; pipe_index = pipe_index + 1) begin
            rdata_pipe_q[pipe_index] <= '0;
          end
        end else begin
          rdata_pipe_q[0] <= sram_rdata;
          for (pipe_index = 1; pipe_index < READ_LATENCY-1; pipe_index = pipe_index + 1) begin
            rdata_pipe_q[pipe_index] <= rdata_pipe_q[pipe_index-1];
          end
        end
      end

      assign rdata_o = rdata_pipe_q[READ_LATENCY-2];
    end
  endgenerate

  assign sram_resp_valid = resp_valid_pipe_q[READ_LATENCY-1];
  assign resp_valid_o = sram_resp_valid;
  assign resp_write_o = resp_write_pipe_q[READ_LATENCY-1];
  assign err_o        = 1'b0;

endmodule
