// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// Blocking physically indexed, physically tagged RV64 D-Cache.
//
// The CPU side permits one request at a time. The backing side transfers one
// complete cache line per request; an AXI4 adapter will replace that interface
// after this line-memory verification milestone.
module dcache #(
  parameter int unsigned PADDR_W_P        = 48,
  parameter int unsigned CACHE_SIZE_BYTES_P = 32 * 1024,
  parameter int unsigned LINE_BYTES_P     = 64,
  parameter int unsigned WAYS_P           = 2
) (
  input  logic                   clk,
  input  logic                   rst_n,

  // CPU-side, one outstanding request maximum.
  input  logic                   cpu_req_i,
  input  logic [PADDR_W_P-1:0]   cpu_addr_i,
  input  logic [63:0]            cpu_wdata_i,
  input  logic                   cpu_we_i,
  input  logic [7:0]             cpu_be_i,
  input  logic [3:0]             cpu_atomic_op_i,
  output logic                   cpu_resp_valid_o,
  output logic [63:0]            cpu_rdata_o,
  output logic                   cpu_err_o,

  // Clean all dirty lines. A flush retains valid clean lines.
  input  logic                   flush_i,
  output logic                   flush_done_o,
  output logic                   flush_err_o,

  // Zicbom one-line maintenance. A CBO never allocates a missing line.
  input  logic                   cbo_req_i,
  input  logic [PADDR_W_P-1:0]   cbo_addr_i,
  input  logic [1:0]             cbo_op_i,
  output logic                   cbo_ready_o,
  output logic                   cbo_done_o,
  output logic                   cbo_err_o,

  // Full-line backing-memory transaction.
  output logic                   line_req_o,
  output logic                   line_we_o,
  output logic [PADDR_W_P-1:0]   line_addr_o,
  output logic [LINE_BYTES_P*8-1:0] line_wdata_o,
  input  logic                   line_resp_valid_i,
  input  logic [LINE_BYTES_P*8-1:0] line_rdata_i,
  input  logic                   line_err_i
);

  localparam int unsigned LINE_BITS = LINE_BYTES_P * 8;
  localparam int unsigned SETS_P = CACHE_SIZE_BYTES_P / (LINE_BYTES_P * WAYS_P);
  localparam int unsigned OFFSET_W = $clog2(LINE_BYTES_P);
  localparam int unsigned SET_W = $clog2(SETS_P);
  localparam int unsigned TAG_W = PADDR_W_P - OFFSET_W - SET_W;

  localparam logic [3:0] ATOMIC_NONE = 4'd0;
  localparam logic [3:0] ATOMIC_LR   = 4'd1;
  localparam logic [3:0] ATOMIC_SC   = 4'd2;
  localparam logic [3:0] ATOMIC_SWAP = 4'd3;
  localparam logic [3:0] ATOMIC_ADD  = 4'd4;
  localparam logic [3:0] ATOMIC_XOR  = 4'd5;
  localparam logic [3:0] ATOMIC_AND  = 4'd6;
  localparam logic [3:0] ATOMIC_OR   = 4'd7;
  localparam logic [3:0] ATOMIC_MIN  = 4'd8;
  localparam logic [3:0] ATOMIC_MAX  = 4'd9;
  localparam logic [3:0] ATOMIC_MINU = 4'd10;
  localparam logic [3:0] ATOMIC_MAXU = 4'd11;

  localparam logic [1:0] CBO_NONE  = 2'd0;
  localparam logic [1:0] CBO_INVAL = 2'd1;
  localparam logic [1:0] CBO_CLEAN = 2'd2;
  localparam logic [1:0] CBO_FLUSH = 2'd3;

  typedef enum logic [3:0] {
    DC_IDLE,
    DC_LOOKUP,
    DC_WRITEBACK_REQ,
    DC_WRITEBACK_WAIT,
    DC_REFILL_REQ,
    DC_REFILL_WAIT,
    DC_RESP,
    DC_FLUSH_SCAN,
    DC_FLUSH_WRITEBACK_REQ,
    DC_FLUSH_WRITEBACK_WAIT,
    DC_FLUSH_DONE,
    DC_CBO_LOOKUP,
    DC_CBO_WRITEBACK_REQ,
    DC_CBO_WRITEBACK_WAIT,
    DC_CBO_DONE
  } dcache_state_e;

  dcache_state_e state_q;

  // Kept as simple behavioral arrays so FPGA synthesis may infer BRAM/URAM
  // after replacing the asynchronous lookup with the target RAM macro path.
  logic [LINE_BITS-1:0] data_q [0:WAYS_P-1][0:SETS_P-1];
  logic [TAG_W-1:0] tag_q [0:WAYS_P-1][0:SETS_P-1];
  logic [WAYS_P-1:0] valid_q [0:SETS_P-1];
  logic [WAYS_P-1:0] dirty_q [0:SETS_P-1];
  logic [$clog2(WAYS_P)-1:0] victim_q [0:SETS_P-1];

  logic [PADDR_W_P-1:0] req_addr_q;
  logic [PADDR_W_P-1:0] cbo_addr_q;
  logic [1:0]           cbo_op_q;
  logic [63:0]          req_wdata_q;
  logic                 req_we_q;
  logic [7:0]           req_be_q;
  logic [3:0]           req_atomic_op_q;
  logic [$clog2(WAYS_P)-1:0] refill_way_q;
  logic [SET_W-1:0]     flush_set_q;
  logic [$clog2(WAYS_P)-1:0] flush_way_q;
  logic [63:0]          response_rdata_q;
  logic                 response_err_q;
  logic                 flush_err_q;
  logic                 cbo_err_q;
  logic                 reservation_valid_q;
  logic [PADDR_W_P-1:OFFSET_W] reservation_line_q;

  logic [SET_W-1:0] req_set;
  logic [SET_W-1:0] cbo_set;
  logic [TAG_W-1:0] cbo_tag;
  logic cbo_lookup_hit;
  logic [$clog2(WAYS_P)-1:0] cbo_lookup_hit_way;
  logic [TAG_W-1:0] req_tag;
  logic [OFFSET_W-1:0] req_line_offset;
  logic [2:0] req_word_index;
  logic atomic_is_word;
  logic atomic_high_word;
  logic sc_success;
  logic lookup_hit;
  logic [$clog2(WAYS_P)-1:0] lookup_hit_way;
  logic [$clog2(WAYS_P)-1:0] lookup_victim_way;
  integer lookup_way_index;
  integer cbo_lookup_way_index;
  integer reset_set_index;

  function automatic logic [LINE_BITS-1:0] apply_store(
    input logic [LINE_BITS-1:0] old_line,
    input logic [OFFSET_W-1:0] byte_offset,
    input logic [63:0] wdata,
    input logic [7:0] be
  );
    logic [LINE_BITS-1:0] next_line;
    integer lane;
    begin
      next_line = old_line;
      for (lane = 0; lane < 8; lane = lane + 1) begin
        if (be[lane])
          next_line[(int'(byte_offset) + lane) * 8 +: 8] = wdata[lane * 8 +: 8];
      end
      return next_line;
    end
  endfunction

  function automatic logic [63:0] apply_atomic(
    input logic [63:0] old_word,
    input logic [63:0] operand,
    input logic [3:0] atomic_op,
    input logic is_word,
    input logic high_word
  );
    logic [63:0] result;
    logic [31:0] old32;
    logic [31:0] operand32;
    logic [31:0] result32;
    begin
      result = old_word;
      if (is_word) begin
        old32 = high_word ? old_word[63:32] : old_word[31:0];
        operand32 = high_word ? operand[63:32] : operand[31:0];
        result32 = operand32;
        unique case (atomic_op)
          ATOMIC_SWAP: result32 = operand32;
          ATOMIC_ADD:  result32 = old32 + operand32;
          ATOMIC_XOR:  result32 = old32 ^ operand32;
          ATOMIC_AND:  result32 = old32 & operand32;
          ATOMIC_OR:   result32 = old32 | operand32;
          ATOMIC_MIN:  result32 = ($signed(old32) < $signed(operand32)) ? old32 : operand32;
          ATOMIC_MAX:  result32 = ($signed(old32) > $signed(operand32)) ? old32 : operand32;
          ATOMIC_MINU: result32 = (old32 < operand32) ? old32 : operand32;
          ATOMIC_MAXU: result32 = (old32 > operand32) ? old32 : operand32;
          default: ;
        endcase
        if (high_word)
          result[63:32] = result32;
        else
          result[31:0] = result32;
      end else begin
        unique case (atomic_op)
          ATOMIC_SWAP: result = operand;
          ATOMIC_ADD:  result = old_word + operand;
          ATOMIC_XOR:  result = old_word ^ operand;
          ATOMIC_AND:  result = old_word & operand;
          ATOMIC_OR:   result = old_word | operand;
          ATOMIC_MIN:  result = ($signed(old_word) < $signed(operand)) ? old_word : operand;
          ATOMIC_MAX:  result = ($signed(old_word) > $signed(operand)) ? old_word : operand;
          ATOMIC_MINU: result = (old_word < operand) ? old_word : operand;
          ATOMIC_MAXU: result = (old_word > operand) ? old_word : operand;
          default: ;
        endcase
      end
      return result;
    end
  endfunction

  assign req_set = req_addr_q[OFFSET_W +: SET_W];
  assign cbo_set = cbo_addr_q[OFFSET_W +: SET_W];
  assign cbo_tag = cbo_addr_q[PADDR_W_P-1 -: TAG_W];
  assign req_tag = req_addr_q[PADDR_W_P-1 -: TAG_W];
  assign req_line_offset = req_addr_q[OFFSET_W-1:0];
  assign req_word_index = req_addr_q[5:3];

  // The request is captured on the DC_IDLE edge. Evaluate the following
  // DC_LOOKUP state against that captured address rather than the previous
  // combinational request view.
  always_comb begin
    lookup_hit = 1'b0;
    lookup_hit_way = '0;
    lookup_victim_way = victim_q[req_set];
    for (lookup_way_index = 0; lookup_way_index < WAYS_P;
         lookup_way_index = lookup_way_index + 1) begin
      if (valid_q[req_set][lookup_way_index] &&
          (tag_q[lookup_way_index][req_set] == req_tag)) begin
        lookup_hit = 1'b1;
        lookup_hit_way = lookup_way_index[$clog2(WAYS_P)-1:0];
      end
      if (!valid_q[req_set][lookup_way_index])
        lookup_victim_way = lookup_way_index[$clog2(WAYS_P)-1:0];
    end
  end

  assign atomic_is_word = req_be_q != 8'hff;
  assign atomic_high_word = atomic_is_word && req_be_q[7];
  assign sc_success = reservation_valid_q &&
                      (reservation_line_q == req_addr_q[PADDR_W_P-1:OFFSET_W]);

  always_comb begin
    cbo_lookup_hit = 1'b0;
    cbo_lookup_hit_way = '0;
    for (cbo_lookup_way_index = 0; cbo_lookup_way_index < WAYS_P;
         cbo_lookup_way_index = cbo_lookup_way_index + 1) begin
      if (valid_q[cbo_set][cbo_lookup_way_index] &&
          (tag_q[cbo_lookup_way_index][cbo_set] == cbo_tag)) begin
        cbo_lookup_hit = 1'b1;
        cbo_lookup_hit_way = cbo_lookup_way_index[$clog2(WAYS_P)-1:0];
      end
    end
  end

  always_comb begin
    line_req_o = 1'b0;
    line_we_o = 1'b0;
    line_addr_o = '0;
    line_wdata_o = '0;

    unique case (state_q)
      DC_WRITEBACK_REQ: begin
        line_req_o = 1'b1;
        line_we_o = 1'b1;
        line_addr_o = {tag_q[refill_way_q][req_set], req_set, {OFFSET_W{1'b0}}};
        line_wdata_o = data_q[refill_way_q][req_set];
      end
      DC_REFILL_REQ: begin
        line_req_o = 1'b1;
        line_addr_o = {req_addr_q[PADDR_W_P-1:OFFSET_W], {OFFSET_W{1'b0}}};
      end
      DC_FLUSH_WRITEBACK_REQ: begin
        line_req_o = 1'b1;
        line_we_o = 1'b1;
        line_addr_o = {tag_q[flush_way_q][flush_set_q], flush_set_q, {OFFSET_W{1'b0}}};
        line_wdata_o = data_q[flush_way_q][flush_set_q];
      end
      DC_CBO_WRITEBACK_REQ: begin
        line_req_o = 1'b1;
        line_we_o = 1'b1;
        line_addr_o = {tag_q[cbo_lookup_hit_way][cbo_set], cbo_set, {OFFSET_W{1'b0}}};
        line_wdata_o = data_q[cbo_lookup_hit_way][cbo_set];
      end
      default: ;
    endcase
  end

  assign cpu_resp_valid_o = state_q == DC_RESP;
  assign cpu_rdata_o = response_rdata_q;
  assign cpu_err_o = response_err_q;
  assign flush_done_o = state_q == DC_FLUSH_DONE;
  assign flush_err_o = flush_err_q;
  assign cbo_ready_o = (state_q == DC_IDLE) && !flush_i && !cpu_req_i;
  assign cbo_done_o = state_q == DC_CBO_DONE;
  assign cbo_err_o = cbo_err_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= DC_IDLE;
      req_addr_q <= '0;
      cbo_addr_q <= '0;
      cbo_op_q <= CBO_NONE;
      req_wdata_q <= '0;
      req_we_q <= 1'b0;
      req_be_q <= '0;
      req_atomic_op_q <= ATOMIC_NONE;
      refill_way_q <= '0;
      flush_set_q <= '0;
      flush_way_q <= '0;
      response_rdata_q <= '0;
      response_err_q <= 1'b0;
      flush_err_q <= 1'b0;
      cbo_err_q <= 1'b0;
      reservation_valid_q <= 1'b0;
      reservation_line_q <= '0;
      for (reset_set_index = 0; reset_set_index < SETS_P;
           reset_set_index = reset_set_index + 1) begin
        valid_q[reset_set_index] = '0;
        dirty_q[reset_set_index] = '0;
        victim_q[reset_set_index] = '0;
      end
    end else begin
      unique case (state_q)
        DC_IDLE: begin
          if (flush_i) begin
            flush_set_q <= '0;
            flush_way_q <= '0;
            flush_err_q <= 1'b0;
            reservation_valid_q <= 1'b0;
            state_q <= DC_FLUSH_SCAN;
          end else if (cbo_req_i) begin
            cbo_addr_q <= cbo_addr_i;
            cbo_op_q <= cbo_op_i;
            cbo_err_q <= 1'b0;
            state_q <= DC_CBO_LOOKUP;
          end else if (cpu_req_i) begin
            req_addr_q <= cpu_addr_i;
            req_wdata_q <= cpu_wdata_i;
            req_we_q <= cpu_we_i;
            req_be_q <= cpu_be_i;
            req_atomic_op_q <= cpu_atomic_op_i;
            response_err_q <= 1'b0;
            state_q <= DC_LOOKUP;
          end
        end

        DC_LOOKUP: begin
          if (lookup_hit) begin
            response_rdata_q <= data_q[lookup_hit_way][req_set][req_word_index * 64 +: 64];
            response_err_q <= 1'b0;
            victim_q[req_set] <= (lookup_hit_way == $clog2(WAYS_P)'(WAYS_P - 1)) ?
                                 '0 : lookup_hit_way + 1'b1;
            if ((req_we_q || (req_atomic_op_q != ATOMIC_NONE)) &&
                reservation_valid_q &&
                (reservation_line_q == req_addr_q[PADDR_W_P-1:OFFSET_W])) begin
              reservation_valid_q <= 1'b0;
            end

            unique case (req_atomic_op_q)
              ATOMIC_NONE: begin
                if (req_we_q) begin
                  // The CPU D-bus already shifts store data and byte enables
                  // by addr[2:0].  Apply them at the containing 64-bit word
                  // base; adding req_line_offset again would double-shift
                  // SB/SH/SW and AMO.W accesses.
                  data_q[lookup_hit_way][req_set] <=
                      apply_store(data_q[lookup_hit_way][req_set],
                                  {req_line_offset[OFFSET_W-1:3], 3'b000},
                                  req_wdata_q, req_be_q);
                  dirty_q[req_set][lookup_hit_way] <= 1'b1;
                end
              end
              ATOMIC_LR: begin
                reservation_valid_q <= 1'b1;
                reservation_line_q <= req_addr_q[PADDR_W_P-1:OFFSET_W];
              end
              ATOMIC_SC: begin
                reservation_valid_q <= 1'b0;
                response_rdata_q <= {{63{1'b0}}, !sc_success};
                if (sc_success) begin
                  data_q[lookup_hit_way][req_set] <=
                      apply_store(data_q[lookup_hit_way][req_set],
                                  {req_line_offset[OFFSET_W-1:3], 3'b000},
                                  req_wdata_q, req_be_q);
                  dirty_q[req_set][lookup_hit_way] <= 1'b1;
                end
              end
              default: begin
                data_q[lookup_hit_way][req_set] <=
                    apply_store(data_q[lookup_hit_way][req_set],
                                {req_line_offset[OFFSET_W-1:3], 3'b000},
                                apply_atomic(
                                  data_q[lookup_hit_way][req_set][req_word_index * 64 +: 64],
                                  req_wdata_q, req_atomic_op_q, atomic_is_word,
                                  atomic_high_word), 8'hff);
                dirty_q[req_set][lookup_hit_way] <= 1'b1;
                reservation_valid_q <= 1'b0;
              end
            endcase
            state_q <= DC_RESP;
          end else begin
            refill_way_q <= lookup_victim_way;
            if (valid_q[req_set][lookup_victim_way] && dirty_q[req_set][lookup_victim_way])
              state_q <= DC_WRITEBACK_REQ;
            else
              state_q <= DC_REFILL_REQ;
          end
        end

        DC_WRITEBACK_REQ: begin
          // The simple line-memory backend returns its one-cycle response on
          // this same edge. AXI will normally deliver it later; accept both.
          if (line_resp_valid_i) begin
            if (line_err_i) begin
              response_rdata_q <= '0;
              response_err_q <= 1'b1;
              state_q <= DC_RESP;
            end else begin
              dirty_q[req_set][refill_way_q] <= 1'b0;
              state_q <= DC_REFILL_REQ;
            end
          end else begin
            state_q <= DC_WRITEBACK_WAIT;
          end
        end

        DC_WRITEBACK_WAIT: begin
          if (line_resp_valid_i) begin
            if (line_err_i) begin
              response_rdata_q <= '0;
              response_err_q <= 1'b1;
              state_q <= DC_RESP;
            end else begin
              dirty_q[req_set][refill_way_q] <= 1'b0;
              state_q <= DC_REFILL_REQ;
            end
          end
        end

        DC_REFILL_REQ: begin
          if (line_resp_valid_i) begin
            if (line_err_i) begin
              response_rdata_q <= '0;
              response_err_q <= 1'b1;
              state_q <= DC_RESP;
            end else begin
              data_q[refill_way_q][req_set] <= line_rdata_i;
              tag_q[refill_way_q][req_set] <= req_tag;
              valid_q[req_set][refill_way_q] <= 1'b1;
              dirty_q[req_set][refill_way_q] <= 1'b0;
              state_q <= DC_LOOKUP;
            end
          end else begin
            state_q <= DC_REFILL_WAIT;
          end
        end

        DC_REFILL_WAIT: begin
          if (line_resp_valid_i) begin
            if (line_err_i) begin
              response_rdata_q <= '0;
              response_err_q <= 1'b1;
              state_q <= DC_RESP;
            end else begin
              data_q[refill_way_q][req_set] <= line_rdata_i;
              tag_q[refill_way_q][req_set] <= req_tag;
              valid_q[req_set][refill_way_q] <= 1'b1;
              dirty_q[req_set][refill_way_q] <= 1'b0;
              state_q <= DC_LOOKUP;
            end
          end
        end

        // A response is visible throughout DC_RESP. Accept a following CPU
        // request on its closing edge so an in-order pipeline need not insert
        // a bubble after every D-Cache completion.
        DC_RESP: begin
          if (flush_i) begin
            flush_set_q <= '0;
            flush_way_q <= '0;
            flush_err_q <= 1'b0;
            reservation_valid_q <= 1'b0;
            state_q <= DC_FLUSH_SCAN;
          end else if (cpu_req_i) begin
            req_addr_q <= cpu_addr_i;
            req_wdata_q <= cpu_wdata_i;
            req_we_q <= cpu_we_i;
            req_be_q <= cpu_be_i;
            req_atomic_op_q <= cpu_atomic_op_i;
            response_err_q <= 1'b0;
            state_q <= DC_LOOKUP;
          end else begin
            state_q <= DC_IDLE;
          end
        end

        DC_CBO_LOOKUP: begin
          if (cbo_lookup_hit) begin
            if (reservation_valid_q &&
                (reservation_line_q == cbo_addr_q[PADDR_W_P-1:OFFSET_W]))
              reservation_valid_q <= 1'b0;
            unique case (cbo_op_q)
              CBO_INVAL: begin
                valid_q[cbo_set][cbo_lookup_hit_way] <= 1'b0;
                dirty_q[cbo_set][cbo_lookup_hit_way] <= 1'b0;
                state_q <= DC_CBO_DONE;
              end
              CBO_CLEAN: begin
                if (dirty_q[cbo_set][cbo_lookup_hit_way])
                  state_q <= DC_CBO_WRITEBACK_REQ;
                else
                  state_q <= DC_CBO_DONE;
              end
              CBO_FLUSH: begin
                if (dirty_q[cbo_set][cbo_lookup_hit_way])
                  state_q <= DC_CBO_WRITEBACK_REQ;
                else begin
                  valid_q[cbo_set][cbo_lookup_hit_way] <= 1'b0;
                  dirty_q[cbo_set][cbo_lookup_hit_way] <= 1'b0;
                  state_q <= DC_CBO_DONE;
                end
              end
              default: state_q <= DC_CBO_DONE;
            endcase
          end else begin
            state_q <= DC_CBO_DONE;
          end
        end

        DC_CBO_WRITEBACK_REQ: begin
          if (line_resp_valid_i) begin
            if (line_err_i) begin
              cbo_err_q <= 1'b1;
            end else begin
              dirty_q[cbo_set][cbo_lookup_hit_way] <= 1'b0;
              if (cbo_op_q == CBO_FLUSH)
                valid_q[cbo_set][cbo_lookup_hit_way] <= 1'b0;
            end
            state_q <= DC_CBO_DONE;
          end else begin
            state_q <= DC_CBO_WRITEBACK_WAIT;
          end
        end

        DC_CBO_WRITEBACK_WAIT: begin
          if (line_resp_valid_i) begin
            if (line_err_i) begin
              cbo_err_q <= 1'b1;
            end else begin
              dirty_q[cbo_set][cbo_lookup_hit_way] <= 1'b0;
              if (cbo_op_q == CBO_FLUSH)
                valid_q[cbo_set][cbo_lookup_hit_way] <= 1'b0;
            end
            state_q <= DC_CBO_DONE;
          end
        end

        DC_CBO_DONE: begin
          state_q <= DC_IDLE;
        end

        DC_FLUSH_SCAN: begin
          if (valid_q[flush_set_q][flush_way_q] && dirty_q[flush_set_q][flush_way_q])
            state_q <= DC_FLUSH_WRITEBACK_REQ;
          else if (flush_way_q == 1'(WAYS_P - 1)) begin
            flush_way_q <= '0;
            if (flush_set_q == SET_W'(SETS_P - 1))
              state_q <= DC_FLUSH_DONE;
            else begin
              flush_set_q <= flush_set_q + 1'b1;
              state_q <= DC_FLUSH_SCAN;
            end
          end else begin
            flush_way_q <= flush_way_q + 1'b1;
            state_q <= DC_FLUSH_SCAN;
          end
        end

        DC_FLUSH_WRITEBACK_REQ: begin
          if (line_resp_valid_i) begin
            if (line_err_i) begin
              flush_err_q <= 1'b1;
              state_q <= DC_FLUSH_DONE;
            end else begin
              dirty_q[flush_set_q][flush_way_q] <= 1'b0;
              if (flush_way_q == 1'(WAYS_P - 1)) begin
                flush_way_q <= '0;
                if (flush_set_q == SET_W'(SETS_P - 1))
                  state_q <= DC_FLUSH_DONE;
                else begin
                  flush_set_q <= flush_set_q + 1'b1;
                  state_q <= DC_FLUSH_SCAN;
                end
              end else begin
                flush_way_q <= flush_way_q + 1'b1;
                state_q <= DC_FLUSH_SCAN;
              end
            end
          end else begin
            state_q <= DC_FLUSH_WRITEBACK_WAIT;
          end
        end

        DC_FLUSH_WRITEBACK_WAIT: begin
          if (line_resp_valid_i) begin
            if (line_err_i) begin
              flush_err_q <= 1'b1;
              state_q <= DC_FLUSH_DONE;
            end else begin
              dirty_q[flush_set_q][flush_way_q] <= 1'b0;
              if (flush_way_q == 1'(WAYS_P - 1)) begin
                flush_way_q <= '0;
                if (flush_set_q == SET_W'(SETS_P - 1))
                  state_q <= DC_FLUSH_DONE;
                else begin
                  flush_set_q <= flush_set_q + 1'b1;
                  state_q <= DC_FLUSH_SCAN;
                end
              end else begin
                flush_way_q <= flush_way_q + 1'b1;
                state_q <= DC_FLUSH_SCAN;
              end
            end
          end
        end

        DC_FLUSH_DONE: begin
          // Keep completion visible for one full cycle. A requester asserts
          // flush_i until this acknowledgement, then releases it.
          if (!flush_i && cpu_req_i) begin
            req_addr_q <= cpu_addr_i;
            req_wdata_q <= cpu_wdata_i;
            req_we_q <= cpu_we_i;
            req_be_q <= cpu_be_i;
            req_atomic_op_q <= cpu_atomic_op_i;
            response_err_q <= 1'b0;
            state_q <= DC_LOOKUP;
          end else if (!flush_i) begin
            state_q <= DC_IDLE;
          end
        end
        default: state_q <= DC_IDLE;
      endcase
    end
  end

endmodule
