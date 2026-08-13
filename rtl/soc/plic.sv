// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// RISC-V PLIC v1.0.0 subset for eRISCV-M.
//
// 32 global sources, one hart, and one M-mode context. Source ID zero is
// reserved. The implementation exposes standard priority, pending, enable,
// threshold, and claim/complete registers at the standard PLIC offsets.
module plic #(
  parameter int           NUM_SOURCES  = 32,
  parameter int           PRIORITY_BITS = 3,
  parameter logic [31:0] BASE_ADDR    = 32'h0c00_0000
) (
  // Clock and reset
  input  logic        clk,
  input  logic        rst_n,

  // PLIC DBus transaction
  input  logic        req_i,
  input  logic        we_i,
  input  logic [3:0]  be_i,
  input  logic [31:0] addr_i,
  input  logic [31:0] wdata_i,
  output logic        hit_o,
  output logic        write_accept_o,
  output logic        resp_valid_o,
  output logic [31:0] rdata_o,
  output logic        err_o,

  // Interrupt source levels and hart MEIP output
  input  logic [NUM_SOURCES-1:0] src_i,
  output logic        meip_o
);

  // Priority-tree and register-window sizing
  localparam int ID_WIDTH      = $clog2(NUM_SOURCES + 1);
  // Round source count up to a power of two, so the arbitration network has
  // a fixed, balanced topology. Source zero and the padding leaves are
  // permanently invalid.
  localparam int ARBITER_LEAF_COUNT = 1 << $clog2(NUM_SOURCES + 1);
  localparam int ARBITER_NODE_COUNT = (2 * ARBITER_LEAF_COUNT) - 1;
  // Source ID zero is reserved, so source 32 lives in bitmap word 1 bit 0.
  localparam int SOURCE_WORDS  = (NUM_SOURCES / 32) + 1;
  localparam int SOURCE_WORD_INDEX_WIDTH = (SOURCE_WORDS <= 1) ? 1 : $clog2(SOURCE_WORDS);
  localparam logic [31:0] PENDING_BASE = 32'h0000_1000;
  localparam logic [31:0] ENABLE_BASE  = 32'h0000_2000;
  localparam logic [31:0] THRESHOLD_ADDR = 32'h0020_0000;
  localparam logic [31:0] CLAIM_ADDR     = 32'h0020_0004;
  localparam logic [31:0] WINDOW_BYTES   = 32'h0020_1000;

  // DBus address decode
  logic [31:0] local_addr;
  logic        in_window;
  logic        priority_access;
  logic        pending_access;
  logic        enable_access;
  logic        threshold_access;
  logic        claim_access;
  logic        valid_access;
  logic [ID_WIDTH-1:0] priority_id;
  logic [SOURCE_WORD_INDEX_WIDTH-1:0] pending_word;
  logic [SOURCE_WORD_INDEX_WIDTH-1:0] enable_word;

  // Architectural priority, pending, enable, and in-service state
  logic [PRIORITY_BITS-1:0] priority_q [0:NUM_SOURCES];
  logic [PRIORITY_BITS-1:0] priority_d [0:NUM_SOURCES];
  logic [NUM_SOURCES:0] pending_q;
  logic [NUM_SOURCES:0] pending_d;
  logic [NUM_SOURCES:0] enable_q;
  logic [NUM_SOURCES:0] enable_d;
  logic [NUM_SOURCES:0] in_service_q;
  logic [NUM_SOURCES:0] in_service_d;
  logic [PRIORITY_BITS-1:0] threshold_q;
  logic [PRIORITY_BITS-1:0] threshold_d;

  // Priority-arbiter candidate payload
  typedef struct packed {
    logic                     valid;
    logic [PRIORITY_BITS-1:0] priority_value;
    logic [ID_WIDTH-1:0]      id;
  } arbiter_candidate_t;

  // Selected interrupt and DBus write data
  logic [ID_WIDTH-1:0] highest_id;
  // This is an acyclic bottom-up tree: every node reads only higher-indexed
  // children and leaves read registered PLIC state. Verilator cannot infer
  // that ordering from the unpacked array and reports a false UNOPTFLAT loop.
  /* verilator lint_off UNOPTFLAT */
  arbiter_candidate_t arbiter_tree [0:ARBITER_NODE_COUNT-1];
  logic                claim_read;
  logic                claim_complete;
  logic [31:0]         enable_write_data;
  logic [31:0]         priority_write_data;
  logic [31:0]         threshold_write_data;

  function automatic logic [31:0] merge_bytes(
    input logic [31:0] old_value,
    input logic [31:0] new_value,
    input logic [3:0] byte_enable
  );
    logic [31:0] merged;
    begin
      merged = old_value;
      for (int byte_index = 0; byte_index < 4; byte_index++) begin
        if (byte_enable[byte_index]) begin
          merged[byte_index * 8 +: 8] = new_value[byte_index * 8 +: 8];
        end
      end
      merge_bytes = merged;
    end
  endfunction

  function automatic logic [31:0] source_word(
    input logic [NUM_SOURCES:0] sources,
    input int unsigned           word_index
  );
    logic [31:0] value;
    begin
      value = '0;
      for (int source_id = 1; source_id <= NUM_SOURCES; source_id++) begin
        if ((source_id / 32) == word_index) begin
          value[source_id % 32] = sources[source_id];
        end
      end
      source_word = value;
    end
  endfunction

  // Select one source from a pair of candidates. The lower source ID wins
  // ties, matching the PLIC arbitration rule without a serial source scan.
  function automatic arbiter_candidate_t select_winner(
    input arbiter_candidate_t left,
    input arbiter_candidate_t right
  );
    begin
      select_winner = left;
      if (!left.valid || (right.valid &&
          ((right.priority_value > left.priority_value) ||
           ((right.priority_value == left.priority_value) && (right.id < left.id))))) begin
        select_winner = right;
      end
    end
  endfunction

  assign local_addr = addr_i - BASE_ADDR;
  assign in_window = (addr_i >= BASE_ADDR) && (addr_i < (BASE_ADDR + WINDOW_BYTES));
  assign priority_id = local_addr[ID_WIDTH+1:2];
  assign pending_word = local_addr[2 +: SOURCE_WORD_INDEX_WIDTH];
  assign enable_word = local_addr[2 +: SOURCE_WORD_INDEX_WIDTH];
  // Priority register 0 is reserved but architecturally readable/writable;
  // Zephyr clears it during PLIC initialization.  Source 0 is never
  // considered by the arbitration loop below.
  assign priority_access = in_window && (local_addr <= (NUM_SOURCES * 4)) &&
                           (local_addr[1:0] == 2'b00);
  assign pending_access = in_window && (local_addr >= PENDING_BASE) &&
                          (local_addr < (PENDING_BASE + SOURCE_WORDS * 4)) && (local_addr[1:0] == 2'b00);
  assign enable_access = in_window && (local_addr >= ENABLE_BASE) &&
                         (local_addr < (ENABLE_BASE + SOURCE_WORDS * 4)) && (local_addr[1:0] == 2'b00);
  assign threshold_access = in_window && (local_addr == THRESHOLD_ADDR);
  assign claim_access = in_window && (local_addr == CLAIM_ADDR);
  assign valid_access = priority_access || pending_access || enable_access ||
                        threshold_access || claim_access;
  assign hit_o = in_window;
  assign write_accept_o = req_i && we_i && valid_access;

  // Leaf candidates perform the PLIC eligibility check. The binary tree
  // below then performs log2(N) winner selections instead of serial priority
  // and source-ID scans, shortening the PLIC's register-to-register paths.
  for (genvar source_id = 0; source_id < ARBITER_LEAF_COUNT; source_id++) begin : g_arbiter_leaves
    localparam int LEAF_INDEX = ARBITER_LEAF_COUNT - 1 + source_id;
    if ((source_id > 0) && (source_id <= NUM_SOURCES)) begin : g_source
      assign arbiter_tree[LEAF_INDEX].valid = pending_q[source_id] &&
                                                enable_q[source_id] &&
                                                !in_service_q[source_id] &&
                                                (priority_q[source_id] > threshold_q);
      assign arbiter_tree[LEAF_INDEX].priority_value = priority_q[source_id];
      assign arbiter_tree[LEAF_INDEX].id = ID_WIDTH'(source_id);
    end else begin : g_padding
      assign arbiter_tree[LEAF_INDEX] = '0;
    end
  end

  for (genvar node_id = 0; node_id < ARBITER_LEAF_COUNT - 1; node_id++) begin : g_arbiter_nodes
    assign arbiter_tree[node_id] = select_winner(arbiter_tree[(2 * node_id) + 1],
                                                  arbiter_tree[(2 * node_id) + 2]);
  end

  assign highest_id = arbiter_tree[0].id;
  /* verilator lint_on UNOPTFLAT */

  assign meip_o = (highest_id != '0);
  assign claim_read = req_i && !we_i && claim_access;
  assign claim_complete = req_i && we_i && claim_access &&
                          (wdata_i != 32'd0) && (wdata_i <= NUM_SOURCES);
  assign enable_write_data = merge_bytes(source_word(enable_q, int'(enable_word)), wdata_i, be_i);

  always_comb begin
    for (int source_id = 0; source_id <= NUM_SOURCES; source_id++) begin
      priority_d[source_id] = priority_q[source_id];
    end
    pending_d = pending_q;
    enable_d = enable_q;
    in_service_d = in_service_q;
    threshold_d = threshold_q;
    priority_write_data = '0;
    threshold_write_data = '0;

    // A level-high source becomes pending until it is claimed. After complete,
    // a still-asserted source is observed again on the following cycle.
    for (int source_id = 1; source_id <= NUM_SOURCES; source_id++) begin
      if (src_i[source_id - 1] && !in_service_q[source_id]) begin
        pending_d[source_id] = 1'b1;
      end
    end

    if (req_i && we_i && priority_access) begin
      priority_write_data = merge_bytes(
        {{(32-PRIORITY_BITS){1'b0}}, priority_q[priority_id]}, wdata_i, be_i
      );
      priority_d[priority_id] = priority_write_data[PRIORITY_BITS-1:0];
    end

    if (req_i && we_i && enable_access) begin
      for (int source_id = 1; source_id <= NUM_SOURCES; source_id++) begin
        if ((source_id / 32) == int'(enable_word)) begin
          enable_d[source_id] = enable_write_data[source_id % 32];
        end
      end
    end

    if (req_i && we_i && threshold_access) begin
      threshold_write_data = merge_bytes(
        {{(32-PRIORITY_BITS){1'b0}}, threshold_q}, wdata_i, be_i
      );
      threshold_d = threshold_write_data[PRIORITY_BITS-1:0];
    end

    if (claim_read && (highest_id != '0)) begin
      pending_d[highest_id] = 1'b0;
      in_service_d[highest_id] = 1'b1;
    end

    if (claim_complete) begin
      in_service_d[wdata_i[ID_WIDTH-1:0]] = 1'b0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int source_id = 0; source_id <= NUM_SOURCES; source_id++) begin
        priority_q[source_id] <= '0;
      end
      pending_q <= '0;
      enable_q <= '0;
      in_service_q <= '0;
      threshold_q <= '0;
      resp_valid_o <= 1'b0;
      rdata_o <= '0;
      err_o <= 1'b0;
    end else begin
      for (int source_id = 0; source_id <= NUM_SOURCES; source_id++) begin
        priority_q[source_id] <= priority_d[source_id];
      end
      pending_q <= pending_d;
      enable_q <= enable_d;
      in_service_q <= in_service_d;
      threshold_q <= threshold_d;

      // Valid writes commit on this edge and are acknowledged immediately by
      // the interconnect. Preserve delayed error responses for invalid PLIC
      // accesses.
      resp_valid_o <= req_i && in_window && (!we_i || !valid_access);
      err_o <= req_i && in_window && !valid_access;
      if (req_i && in_window && !we_i) begin
        if (priority_access) begin
          rdata_o <= {{(32-PRIORITY_BITS){1'b0}}, priority_q[priority_id]};
        end else if (pending_access) begin
          rdata_o <= source_word(pending_q, int'(pending_word));
        end else if (enable_access) begin
          rdata_o <= source_word(enable_q, int'(enable_word));
        end else if (threshold_access) begin
          rdata_o <= {{(32-PRIORITY_BITS){1'b0}}, threshold_q};
        end else if (claim_access) begin
          rdata_o <= {{(32-ID_WIDTH){1'b0}}, highest_id};
        end else begin
          rdata_o <= '0;
        end
      end
    end
  end

endmodule
