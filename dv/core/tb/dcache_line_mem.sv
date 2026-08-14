// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// Full-line backing-memory model for D-Cache verification. It is deliberately
// not a SoC memory-map implementation; the AXI4 adapter replaces this block in
// the next memory-system milestone.
module dcache_line_mem #(
  parameter int unsigned PADDR_W_P = 48,
  parameter int unsigned LINE_BYTES_P = 64,
  parameter int unsigned LINE_ADDR_W_P = 14
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         req_i,
  input  logic                         we_i,
  input  logic [PADDR_W_P-1:0]         addr_i,
  input  logic [LINE_BYTES_P*8-1:0]    wdata_i,
  output logic                         resp_valid_o,
  output logic [LINE_BYTES_P*8-1:0]    rdata_o,
  output logic                         err_o
);

  localparam int unsigned OFFSET_W = $clog2(LINE_BYTES_P);

  (* ram_style = "block", ramstyle = "no_rw_check" *)
  logic [LINE_BYTES_P*8-1:0] mem [0:(1 << LINE_ADDR_W_P)-1];
  logic [LINE_ADDR_W_P-1:0] line_index;

  assign line_index = addr_i[OFFSET_W +: LINE_ADDR_W_P];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      resp_valid_o <= 1'b0;
      rdata_o <= '0;
      err_o <= 1'b0;
    end else begin
      resp_valid_o <= req_i;
      err_o <= 1'b0;
      if (req_i) begin
        rdata_o <= mem[line_index];
        if (we_i)
          mem[line_index] <= wdata_i;
      end
    end
  end

endmodule
