// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// Verification-only asynchronous x16 BPI NOR model. It models the read array
// used by the boot path and leaves program/erase command behavior to a future
// CFI-capable model.
module ap_bpi_nor_model #(
  parameter int unsigned ADDR_W_P = 26,
  parameter int unsigned WORDS_P = 64 * 1024,
  parameter string INIT_FILE_P = ""
) (
  input logic reset_n_i,
  input logic [ADDR_W_P-1:0] addr_i,
  inout wire [15:0] dq_io,
  input logic ce_n_i,
  input logic oe_n_i,
  input logic we_n_i,
  input logic adv_n_i,
  output logic ryby_n_o
);

  logic [15:0] mem [0:WORDS_P-1];
  logic [15:0] read_data;
  logic [ADDR_W_P-1:0] latched_addr_q;
  localparam int unsigned MEM_ADDR_W_P = $clog2(WORDS_P);
  localparam logic [ADDR_W_P-1:0] LAST_WORD_ADDR_P = ADDR_W_P'(WORDS_P - 1);

  initial begin
    if (INIT_FILE_P != "")
      $readmemh(INIT_FILE_P, mem);
  end

  always_comb begin
    if (latched_addr_q <= LAST_WORD_ADDR_P)
      read_data = mem[latched_addr_q[MEM_ADDR_W_P-1:0]];
    else
      read_data = 16'hffff;
  end

  always_ff @(posedge adv_n_i or negedge reset_n_i) begin
    if (!reset_n_i)
      latched_addr_q <= '0;
    else
      latched_addr_q <= addr_i;
  end

  assign dq_io = (reset_n_i && !ce_n_i && !oe_n_i && we_n_i) ? read_data : 16'hzzzz;
  assign ryby_n_o = reset_n_i;

  task automatic preload_word(
    input logic [ADDR_W_P-1:0] word_addr,
    input logic [15:0] word_data
  );
    if (word_addr > LAST_WORD_ADDR_P)
      $fatal(1, "ap_bpi_nor_model: preload address out of range: %h", word_addr);
    mem[word_addr[MEM_ADDR_W_P-1:0]] = word_data;
  endtask

endmodule
