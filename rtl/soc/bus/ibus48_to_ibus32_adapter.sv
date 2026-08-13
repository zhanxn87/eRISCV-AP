// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// The current ITCM occupies the low 4 GiB physical-address aperture. A fetch
// outside that aperture returns an illegal instruction instead of aliasing to
// the low 32 address bits.
module ibus48_to_ibus32_adapter #(
  parameter int unsigned PADDR_W_P = 48
) (
  input  logic                   clk,
  input  logic                   rst_n,
  input  logic                   imem_req_i,
  input  logic [PADDR_W_P-1:0]   imem_addr_i,
  output logic                   imem_ready_o,
  output logic                   imem_rvalid_o,
  output logic [31:0]            imem_rdata_o,

  output logic                   legacy_req_o,
  output logic [31:0]            legacy_addr_o,
  input  logic                   legacy_ready_i,
  input  logic                   legacy_rvalid_i,
  input  logic [31:0]            legacy_rdata_i
);

  logic fault_response_q;
  logic high_addr;

  assign high_addr = |imem_addr_i[PADDR_W_P-1:32];
  assign legacy_req_o = imem_req_i && !high_addr && !fault_response_q;
  assign legacy_addr_o = imem_addr_i[31:0];
  assign imem_ready_o = fault_response_q ? 1'b0 :
                        (high_addr ? 1'b1 : legacy_ready_i);
  assign imem_rvalid_o = fault_response_q ? 1'b1 : legacy_rvalid_i;
  assign imem_rdata_o = fault_response_q ? 32'h0000_0000 : legacy_rdata_i;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      fault_response_q <= 1'b0;
    else if (fault_response_q)
      fault_response_q <= 1'b0;
    else if (imem_req_i && high_addr && imem_ready_o)
      fault_response_q <= 1'b1;
  end

endmodule
