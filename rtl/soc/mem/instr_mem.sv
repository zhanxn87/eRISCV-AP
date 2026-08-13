// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Arbitration adapter for the portable single-port instruction SRAM. Boot
// writes take priority, then DBus, then instruction fetch.
module instr_mem #(
  parameter ADDR_WIDTH = 13,
  parameter DATA_WIDTH = 32,
  parameter READ_LATENCY = 1
) (
  input  logic                  clk,
  input  logic                  rst_n,

  // Instruction-fetch port.
  input  logic                  rd_req_i,
  output logic                  ready_o,
  input  logic [ADDR_WIDTH-1:0] addr_i,
  output logic                  rvalid_o,
  output logic [DATA_WIDTH-1:0] instr_o,

  // Pre-fetch boot-loader write port.
  input  logic                  boot_we_i,
  input  logic [ADDR_WIDTH-1:0] boot_addr_i,
  input  logic [DATA_WIDTH-1:0] boot_wdata_i,
  input  logic [3:0]            boot_be_i,

  // DBus port for reads and byte-enabled writes to the executable IMEM window.
  input  logic                  data_req_i,
  input  logic                  data_we_i,
  input  logic [3:0]            data_be_i,
  input  logic [ADDR_WIDTH-1:0] data_addr_i,
  input  logic [DATA_WIDTH-1:0] data_wdata_i,
  output logic                  data_resp_valid_o,
  output logic [DATA_WIDTH-1:0] data_rdata_o,
  output logic                  data_err_o
);

  // Shared SRAM request tagging: fetch has priority over DBus data access
  localparam logic SRAM_TAG_FETCH = 1'b0;
  localparam logic SRAM_TAG_DBUS  = 1'b1;
  // Physical single-port SRAM transaction and delayed-response routing
  logic sram_en;
  logic sram_we;
  logic [3:0] sram_be;
  logic [ADDR_WIDTH-1:0] sram_addr;
  logic [DATA_WIDTH-1:0] sram_wdata;
  logic sram_resp_req;
  logic sram_resp_tag_i;
  logic sram_resp_valid;
  logic sram_resp_tag_o;
  logic [DATA_WIDTH-1:0] sram_rdata;
  logic [READ_LATENCY-1:0] resp_valid_pipe_q;
  logic resp_tag_pipe_q [0:READ_LATENCY-1];
  integer index;

  // One physical SRAM port: boot writes, then DBus, then fetch.
  assign ready_o = !boot_we_i && !data_req_i;

  always_comb begin
    sram_en = 1'b0;
    sram_we = 1'b0;
    sram_be = '0;
    sram_addr = '0;
    sram_wdata = '0;
    sram_resp_req = 1'b0;
    sram_resp_tag_i = SRAM_TAG_FETCH;

    if (boot_we_i) begin
      sram_en = 1'b1;
      sram_we = 1'b1;
      sram_be = boot_be_i;
      sram_addr = boot_addr_i;
      sram_wdata = boot_wdata_i;
    end else if (data_req_i) begin
      sram_en = 1'b1;
      sram_we = data_we_i;
      sram_be = data_be_i;
      sram_addr = data_addr_i;
      sram_wdata = data_wdata_i;
      sram_resp_req = 1'b1;
      sram_resp_tag_i = SRAM_TAG_DBUS;
    end else if (rd_req_i) begin
      sram_en = 1'b1;
      sram_be = 4'h0;
      sram_addr = addr_i;
      sram_resp_req = 1'b1;
      sram_resp_tag_i = SRAM_TAG_FETCH;
    end
  end

  sram_1rw #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) sram_i (
    .clk    (clk),
    .en_i   (sram_en),
    .we_i   (sram_we),
    .be_i   (sram_be),
    .addr_i (sram_addr),
    .wdata_i(sram_wdata),
    .rdata_o(sram_rdata)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      resp_valid_pipe_q <= '0;
      for (index = 0; index < READ_LATENCY; index = index + 1) begin
        resp_tag_pipe_q[index] <= SRAM_TAG_FETCH;
      end
    end else begin
      resp_valid_pipe_q[0] <= sram_resp_req;
      resp_tag_pipe_q[0] <= sram_resp_tag_i;
      for (index = 1; index < READ_LATENCY; index = index + 1) begin
        resp_valid_pipe_q[index] <= resp_valid_pipe_q[index-1];
        resp_tag_pipe_q[index] <= resp_tag_pipe_q[index-1];
      end
    end
  end

  generate
    if (READ_LATENCY == 1) begin : gen_one_cycle_read
      assign instr_o = sram_rdata;
      assign data_rdata_o = sram_rdata;
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

      assign instr_o = rdata_pipe_q[READ_LATENCY-2];
      assign data_rdata_o = rdata_pipe_q[READ_LATENCY-2];
    end
  endgenerate

  assign sram_resp_valid = resp_valid_pipe_q[READ_LATENCY-1];
  assign sram_resp_tag_o = resp_tag_pipe_q[READ_LATENCY-1];
  assign rvalid_o = sram_resp_valid && (sram_resp_tag_o == SRAM_TAG_FETCH);
  assign data_resp_valid_o = sram_resp_valid && (sram_resp_tag_o == SRAM_TAG_DBUS);
  assign data_err_o        = 1'b0;

endmodule
