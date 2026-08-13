// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// ID-stage conditional-branch predictor.
//
// Direct JALs (including decompressed C.J) redirect immediately. A
// four-entry return-address stack predicts ABI-standard JALR returns.
// Conditional branches use a 64-entry, 2-bit BHT after their first resolved
// execution. Invalid BHT entries retain BTFNT (backward taken, forward
// not-taken) as the deterministic cold-start policy. Conditional outcomes
// remain architectural EX work; EX redirects only when the carried prediction
// is wrong.
module branch_predictor #(
  // When disabled, omit BHT state and retain BTFNT for every conditional
  // branch. Direct-jump prediction remains enabled.
  parameter bit ENABLE_BHT_P = 1'b1,
  // When disabled, omit RAS state and resolve every JALR in EX.
  parameter bit ENABLE_RAS_P = 1'b1,
  parameter int unsigned ADDR_WIDTH_P = riscv_pkg::ADDR_WIDTH
) (
  // Clock and reset
  input  logic        clk,
  input  logic        rst_n,

  // Prediction eligibility
  input  logic        enable_i,
  input  logic        valid_i,
  input  logic        illegal_i,

  // Current normalized instruction
  input  logic [ADDR_WIDTH_P-1:0] pc_i,
  input  logic [31:0] instr_i,
  // Raw C instruction. Keeping its predictable control forms separate from
  // `instr_i` keeps the full decompressor out of the early redirect cone.
  input  logic        compressed_i,
  input  logic [15:0] c_instr_i,

  // Resolved-branch training from EX. The update packet is registered before
  // it reaches the BHT arrays, so EX results never feed ID prediction state in
  // the same cycle.
  input  logic        bht_update_valid_i,
  input  logic [ADDR_WIDTH_P-1:0] bht_update_pc_i,
  input  logic        bht_update_taken_i,

  // Resolved JAL/JALR maintenance for the small return-address stack. These
  // inputs are sampled at the clock edge and do not affect the current query.
  input  logic        ras_push_valid_i,
  input  logic [ADDR_WIDTH_P-1:0] ras_push_addr_i,
  input  logic        ras_pop_valid_i,

  // Redirect result
  output logic        redirect_o,
  output logic [ADDR_WIDTH_P-1:0] redirect_pc_o,

  // Prediction classification carried into EX
  output logic        direct_jump_o,
  output logic        return_pred_valid_o,
  output logic [ADDR_WIDTH_P-1:0] return_pred_target_o,
  output logic        branch_pred_valid_o,
  output logic        branch_pred_taken_o,
  output logic        branch_pred_bht_used_o
);

  localparam int BHT_INDEX_WIDTH = 6;
  localparam int BHT_ENTRIES = 1 << BHT_INDEX_WIDTH;

  // Decoded direct-control instruction forms
  logic        native_jal;
  logic        canonical_return;
  logic        valid_branch;
  logic        c_direct_jump;
  logic        c_conditional_branch;
  logic        c_return;
  logic        return_pred_candidate;

  // Immediate targets used by the static predictor
  logic [ADDR_WIDTH_P-1:0] jal_imm;
  logic [ADDR_WIDTH_P-1:0] branch_imm;
  logic [ADDR_WIDTH_P-1:0] c_jump_imm;
  logic [ADDR_WIDTH_P-1:0] c_branch_imm;

  function automatic logic [1:0] bht_next_counter(
    input logic [1:0] counter_i,
    input logic       taken_i
  );
    begin
      unique case (counter_i)
        2'b00:  bht_next_counter = taken_i ? 2'b01 : 2'b00;
        2'b01:  bht_next_counter = taken_i ? 2'b10 : 2'b00;
        2'b10:  bht_next_counter = taken_i ? 2'b11 : 2'b01;
        default:bht_next_counter = taken_i ? 2'b11 : 2'b10;
      endcase
    end
  endfunction

  // Fold higher PC bits into the fixed 64-entry table index. This avoids
  // systematic aliases between nearby branch sites without increasing BHT
  // state. Query and EX training share this helper by construction.
  function automatic logic [BHT_INDEX_WIDTH-1:0] bht_index(
    input logic [ADDR_WIDTH_P-1:0] pc
  );
    begin
      bht_index = pc[6:1] ^ pc[12:7];
    end
  endfunction

  // C.J and C.BEQZ/C.BNEZ are the only compressed forms predicted in
  // ID. Their immediate bit layouts are encoded directly here so the full
  // RV64 decompressor remains on the ID/EX decode path, not the PC redirect
  // path. C.JR x1/x5 preserves the existing RAS-return prediction.
  assign c_direct_jump = (c_instr_i[1:0] == 2'b01) &&
                         (c_instr_i[15:13] == 3'b101);
  assign c_conditional_branch = (c_instr_i[1:0] == 2'b01) &&
                                ((c_instr_i[15:13] == 3'b110) ||
                                 (c_instr_i[15:13] == 3'b111));
  assign c_return = (c_instr_i[1:0] == 2'b10) &&
                    (c_instr_i[15:12] == 4'b1000) &&
                    (c_instr_i[6:2] == 5'd0) &&
                    ((c_instr_i[11:7] == 5'd1) ||
                     (c_instr_i[11:7] == 5'd5));
  assign c_jump_imm = {{(ADDR_WIDTH_P-12){c_instr_i[12]}}, c_instr_i[12], c_instr_i[8],
                       c_instr_i[10:9], c_instr_i[6], c_instr_i[7],
                       c_instr_i[2], c_instr_i[11], c_instr_i[5:3], 1'b0};
  assign c_branch_imm = {{(ADDR_WIDTH_P-9){c_instr_i[12]}}, c_instr_i[12], c_instr_i[6:5],
                         c_instr_i[2], c_instr_i[11:10], c_instr_i[4:3], 1'b0};
  assign jal_imm = compressed_i ? c_jump_imm :
                   {{(ADDR_WIDTH_P-21){instr_i[31]}}, instr_i[31], instr_i[19:12],
                    instr_i[20], instr_i[30:21], 1'b0};
  assign branch_imm = compressed_i ? c_branch_imm :
                      {{(ADDR_WIDTH_P-13){instr_i[31]}}, instr_i[31], instr_i[7],
                       instr_i[30:25], instr_i[11:8], 1'b0};
  assign native_jal = compressed_i ? c_direct_jump : (instr_i[6:0] == 7'b110_1111);
  assign canonical_return = compressed_i ? c_return :
                            ((instr_i[6:0] == 7'b110_0111) &&
                             (instr_i[11:7] == 5'd0) &&
                             ((instr_i[19:15] == 5'd1) ||
                              (instr_i[19:15] == 5'd5)) &&
                             (instr_i[31:20] == 12'd0));
  assign valid_branch = compressed_i ? c_conditional_branch :
                        ((instr_i[6:0] == 7'b110_0011) &&
                         (instr_i[14:12] != 3'b010) &&
                         (instr_i[14:12] != 3'b011));

  generate
    if (ENABLE_BHT_P) begin : g_bht
      // Counters are reset-free and valid bits provide deterministic BTFNT
      // cold start. The generated-off branch contains no BHT state or update
      // logic, rather than merely blocking the prediction result.
      logic [1:0] bht_counter_q [0:BHT_ENTRIES-1];
      logic [BHT_ENTRIES-1:0] bht_valid_q;

      // Registered EX-to-ID training packet
      logic bht_train_valid_q;
      logic [BHT_INDEX_WIDTH-1:0] bht_train_index_q;
      logic bht_train_taken_q;

      // Current ID-stage query
      logic [BHT_INDEX_WIDTH-1:0] bht_query_index;
      logic [BHT_INDEX_WIDTH-1:0] bht_update_index;
      logic bht_query_valid;
      logic bht_query_taken;

      assign bht_query_index = bht_index(pc_i);
      assign bht_update_index = bht_index(bht_update_pc_i);
      assign bht_query_valid = bht_valid_q[bht_query_index];
      assign bht_query_taken = bht_counter_q[bht_query_index][1];

      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          bht_train_valid_q <= 1'b0;
        end else begin
          bht_train_valid_q <= bht_update_valid_i;
        end
      end

      // Payload registers are reset-free because bht_train_valid_q gates all
      // use of their contents.
      always_ff @(posedge clk) begin
        if (bht_update_valid_i) begin
          bht_train_index_q <= bht_update_index;
          bht_train_taken_q <= bht_update_taken_i;
        end
      end

      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          bht_valid_q <= '0;
        end else if (bht_train_valid_q) begin
          bht_valid_q[bht_train_index_q] <= 1'b1;
        end
      end

      // The counter array intentionally has no reset; bht_valid_q gates every
      // read until an entry has received its first update.
      always_ff @(posedge clk) begin
        if (bht_train_valid_q) begin
          if (bht_valid_q[bht_train_index_q])
            bht_counter_q[bht_train_index_q] <= bht_next_counter(
              bht_counter_q[bht_train_index_q], bht_train_taken_q
            );
          else
            bht_counter_q[bht_train_index_q] <=
                bht_train_taken_q ? 2'b10 : 2'b01;
        end
      end

      assign branch_pred_bht_used_o = branch_pred_valid_o && bht_query_valid;
      assign branch_pred_taken_o = branch_pred_valid_o &&
                                   (bht_query_valid ? bht_query_taken : branch_imm[ADDR_WIDTH_P-1]);
    end else begin : g_no_bht
      assign branch_pred_bht_used_o = 1'b0;
      assign branch_pred_taken_o = branch_pred_valid_o && branch_imm[ADDR_WIDTH_P-1];
    end
  endgenerate

  generate
    if (ENABLE_RAS_P) begin : g_ras
      logic        ras_valid;
      logic [ADDR_WIDTH_P-1:0] ras_top_addr;

      return_address_stack #(
        .DEPTH_P(4),
        .ADDR_WIDTH_P(ADDR_WIDTH_P)
      ) return_address_stack_i (
        .clk         (clk),
        .rst_n       (rst_n),
        .push_valid_i(ras_push_valid_i),
        .push_addr_i (ras_push_addr_i),
        .pop_valid_i (ras_pop_valid_i),
        .valid_o     (ras_valid),
        .top_addr_o  (ras_top_addr)
      );

      // `enable_i` can depend on an older EX redirect.  Keep that issue
      // qualification out of the return-target mux: redirect_pc_o is ignored
      // whenever redirect_o is low, while a qualified redirect still uses the
      // identical RAS target.
      assign return_pred_candidate = valid_i && !illegal_i && canonical_return && ras_valid;
      assign return_pred_valid_o = enable_i && return_pred_candidate;
      assign return_pred_target_o = ras_top_addr;
    end else begin : g_no_ras
      assign return_pred_candidate = 1'b0;
      assign return_pred_valid_o  = 1'b0;
      assign return_pred_target_o = '0;
    end
  endgenerate

  assign direct_jump_o = enable_i && valid_i && !illegal_i && native_jal;
  assign branch_pred_valid_o = enable_i && valid_i && !illegal_i && valid_branch;
  assign redirect_o = direct_jump_o || return_pred_valid_o || branch_pred_taken_o;
  // Keep issue qualification out of the redirect-address data path. `enable_i`
  // and the flush/stall signals behind it can depend on older pipeline state;
  // they qualify redirect_o, while this address mux depends only on the ID
  // instruction and registered RAS state. The address is ignored whenever
  // redirect_o is low.
  assign redirect_pc_o = return_pred_candidate ? return_pred_target_o :
                         pc_i + (native_jal ? jal_imm : branch_imm);

endmodule
