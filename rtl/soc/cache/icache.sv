// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// Blocking physically indexed, physically tagged RV64 instruction cache.
//
// The core instruction bus transfers one aligned 32-bit word at a time.  The
// backing interface transfers a complete 64-byte line, which is converted to
// an eight-beat 64-bit AXI read burst by cache_axi4_line_adapter.
module icache #(
  parameter int unsigned PADDR_W_P = 48,
  parameter int unsigned CACHE_SIZE_BYTES_P = 32 * 1024,
  parameter int unsigned LINE_BYTES_P = 64,
  parameter int unsigned WAYS_P = 2
) (
  input  logic                         clk,
  input  logic                         rst_n,

  input  logic                         cpu_req_i,
  input  logic [PADDR_W_P-1:0]         cpu_addr_i,
  input  logic                         invalidate_i,
  output logic                         invalidate_done_o,
  output logic                         cpu_ready_o,
  output logic                         cpu_rvalid_o,
  output logic [31:0]                  cpu_rdata_o,
  output logic                         cpu_err_o,

  output logic                         line_req_o,
  output logic [PADDR_W_P-1:0]         line_addr_o,
  input  logic                         line_resp_valid_i,
  input  logic [LINE_BYTES_P*8-1:0]    line_rdata_i,
  input  logic                         line_err_i
);

  localparam int unsigned LINE_BITS_P = LINE_BYTES_P * 8;
  localparam int unsigned SETS_P = CACHE_SIZE_BYTES_P / (LINE_BYTES_P * WAYS_P);
  localparam int unsigned OFFSET_W = $clog2(LINE_BYTES_P);
  localparam int unsigned SET_W = $clog2(SETS_P);
  localparam int unsigned TAG_W = PADDR_W_P - OFFSET_W - SET_W;

  typedef enum logic [2:0] {
    IC_IDLE,
    IC_LOOKUP,
    IC_REFILL_REQ,
    IC_REFILL_WAIT,
    IC_RESP
  } icache_state_e;

  icache_state_e state_q;
  logic [LINE_BITS_P-1:0] data_q [0:WAYS_P-1][0:SETS_P-1];
  logic [TAG_W-1:0] tag_q [0:WAYS_P-1][0:SETS_P-1];
  logic [WAYS_P-1:0] valid_q [0:SETS_P-1];
  logic [$clog2(WAYS_P)-1:0] victim_q [0:SETS_P-1];

  logic [PADDR_W_P-1:0] req_addr_q;
  logic [SET_W-1:0] req_set;
  logic [TAG_W-1:0] req_tag;
  logic [$clog2(LINE_BYTES_P / 4)-1:0] req_word;
  logic lookup_hit;
  logic [$clog2(WAYS_P)-1:0] lookup_way;
  logic [$clog2(WAYS_P)-1:0] refill_way_q;
  logic [31:0] response_rdata_q;
  logic response_err_q;
  integer way_index;
  integer set_index;

  initial begin
    if ((CACHE_SIZE_BYTES_P % (LINE_BYTES_P * WAYS_P)) != 0)
      $fatal(1, "icache: cache geometry must contain an integral number of sets");
    if (WAYS_P < 2)
      $fatal(1, "icache: at least two ways are required by the AP contract");
  end

  assign req_set = req_addr_q[OFFSET_W +: SET_W];
  assign req_tag = req_addr_q[PADDR_W_P-1 -: TAG_W];
  assign req_word = req_addr_q[OFFSET_W-1:2];

  always_comb begin
    lookup_hit = 1'b0;
    lookup_way = victim_q[req_set];
    for (way_index = 0; way_index < WAYS_P; way_index = way_index + 1) begin
      if (valid_q[req_set][way_index] && tag_q[way_index][req_set] == req_tag) begin
        lookup_hit = 1'b1;
        lookup_way = way_index[$clog2(WAYS_P)-1:0];
      end
      if (!valid_q[req_set][way_index])
        lookup_way = way_index[$clog2(WAYS_P)-1:0];
    end
  end

  // A FENCE/FENCE.I keeps the cache invalidation request asserted until the
  // D-Cache drain and this idle acknowledgement are both observed.
  assign invalidate_done_o = invalidate_i && state_q == IC_IDLE;
  assign cpu_ready_o = state_q == IC_IDLE && !invalidate_i;
  assign cpu_rvalid_o = state_q == IC_RESP;
  assign cpu_rdata_o = response_rdata_q;
  assign cpu_err_o = response_err_q;
  assign line_req_o = state_q == IC_REFILL_REQ;
  assign line_addr_o = {req_addr_q[PADDR_W_P-1:OFFSET_W], {OFFSET_W{1'b0}}};

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= IC_IDLE;
      req_addr_q <= '0;
      refill_way_q <= '0;
      response_rdata_q <= 32'h0000_0013;
      response_err_q <= 1'b0;
      for (set_index = 0; set_index < SETS_P; set_index = set_index + 1) begin
        valid_q[set_index] = '0;
        victim_q[set_index] = '0;
      end
    end else if (invalidate_i && state_q == IC_IDLE) begin
      for (set_index = 0; set_index < SETS_P; set_index = set_index + 1)
        valid_q[set_index] = '0;
    end else begin
      unique case (state_q)
        IC_IDLE: begin
          if (cpu_req_i) begin
            req_addr_q <= cpu_addr_i;
            response_err_q <= 1'b0;
            state_q <= IC_LOOKUP;
          end
        end
        IC_LOOKUP: begin
          if (lookup_hit) begin
            response_rdata_q <= data_q[lookup_way][req_set][req_word * 32 +: 32];
            response_err_q <= 1'b0;
            victim_q[req_set] <= lookup_way + 1'b1;
            state_q <= IC_RESP;
          end else begin
            refill_way_q <= lookup_way;
            state_q <= IC_REFILL_REQ;
          end
        end
        IC_REFILL_REQ: state_q <= IC_REFILL_WAIT;
        IC_REFILL_WAIT: begin
          if (line_resp_valid_i) begin
            if (line_err_i) begin
              response_rdata_q <= 32'h0000_0013;
              response_err_q <= 1'b1;
            end else begin
              data_q[refill_way_q][req_set] <= line_rdata_i;
              tag_q[refill_way_q][req_set] <= req_tag;
              valid_q[req_set][refill_way_q] <= 1'b1;
              victim_q[req_set] <= refill_way_q + 1'b1;
              response_rdata_q <= line_rdata_i[req_word * 32 +: 32];
              response_err_q <= 1'b0;
            end
            state_q <= IC_RESP;
          end
        end
        IC_RESP: state_q <= IC_IDLE;
        default: state_q <= IC_IDLE;
      endcase
    end
  end

endmodule
