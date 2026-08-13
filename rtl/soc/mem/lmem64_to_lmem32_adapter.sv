// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// Build an aligned 64-bit local-memory response from the two word-wide DTCM
// accesses. The core only observes acceptance when the lower word was granted,
// so an unaccepted candidate still falls back to the normal D-bus path.
module lmem64_to_lmem32_adapter #(
  parameter int unsigned PADDR_W_P = 48
) (
  input  logic                   clk,
  input  logic                   rst_n,

  input  logic                   lmem_req_i,
  input  logic [PADDR_W_P-1:0]   lmem_addr_i,
  output logic                   lmem_accept_o,
  output logic                   lmem_resp_valid_o,
  output logic [63:0]            lmem_rdata_o,
  output logic                   lmem_err_o,

  output logic                   legacy_req_o,
  output logic [31:0]            legacy_addr_o,
  input  logic                   legacy_accept_i,
  input  logic                   legacy_resp_valid_i,
  input  logic [31:0]            legacy_rdata_i,
  input  logic                   legacy_err_i
);

  typedef enum logic [2:0] {
    LMEM_IDLE,
    LMEM_LOW_WAIT,
    LMEM_HIGH_ISSUE,
    LMEM_HIGH_WAIT,
    LMEM_RESP
  } lmem_state_e;

  lmem_state_e state_q;
  logic [31:0] base_addr_q;
  logic [63:0] rdata_q;
  logic        err_q;

  assign legacy_req_o = ((state_q == LMEM_IDLE) && lmem_req_i) ||
                        (state_q == LMEM_HIGH_ISSUE);
  assign legacy_addr_o = (state_q == LMEM_HIGH_ISSUE) ?
                         (base_addr_q + 32'd4) : {lmem_addr_i[31:3], 3'b000};
  assign lmem_accept_o = (state_q == LMEM_IDLE) && lmem_req_i && legacy_accept_i;
  assign lmem_resp_valid_o = state_q == LMEM_RESP;
  assign lmem_rdata_o = rdata_q;
  assign lmem_err_o = err_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= LMEM_IDLE;
      base_addr_q <= '0;
      rdata_q <= '0;
      err_q <= 1'b0;
    end else begin
      unique case (state_q)
        LMEM_IDLE: begin
          if (lmem_req_i && legacy_accept_i) begin
            base_addr_q <= {lmem_addr_i[31:3], 3'b000};
            rdata_q <= '0;
            err_q <= 1'b0;
            state_q <= LMEM_LOW_WAIT;
          end
        end

        LMEM_LOW_WAIT: begin
          if (legacy_resp_valid_i) begin
            rdata_q[31:0] <= legacy_rdata_i;
            err_q <= legacy_err_i;
            state_q <= LMEM_HIGH_ISSUE;
          end
        end

        LMEM_HIGH_ISSUE: begin
          if (legacy_accept_i)
            state_q <= LMEM_HIGH_WAIT;
        end

        LMEM_HIGH_WAIT: begin
          if (legacy_resp_valid_i) begin
            rdata_q[63:32] <= legacy_rdata_i;
            err_q <= err_q | legacy_err_i;
            state_q <= LMEM_RESP;
          end
        end

        LMEM_RESP: state_q <= LMEM_IDLE;
        default: state_q <= LMEM_IDLE;
      endcase
    end
  end

endmodule
