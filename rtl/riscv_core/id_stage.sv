// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

import riscv_pkg::*;

// Instruction decode stage wrapper.
// It couples the register file with the decoder and registers the packed ID/EX bus.
// Compressed (C-extension) instructions are decompressed to 32-bit equivalents
// before the decoder sees them.
module id_stage #(
  parameter bit ENABLE_BHT_P = 1'b1,
  parameter bit ENABLE_RAS_P = 1'b1
) (
  // Clock and reset
  input  logic        clk,
  input  logic        rst_n,

  // IF/ID -> ID/EX pipeline boundary
  input  var if_id_t if_id_i,
  input  logic        id_ex_en_i,
  input  logic        id_ex_flush_i,
  output id_ex_t      id_ex_o,

  // WB register-file writeback
  input  logic        wb_we_i,
  input  logic [4:0]  wb_rd_addr_i,
  input  xlen_t       wb_rd_data_i,

  // Debug GPR access
  input  logic [4:0]  dbg_gpr_raddr_i,
  output xlen_t       dbg_gpr_rdata_o,
  input  logic [4:0]  dbg_gpr_waddr_i,
  input  xlen_t       dbg_gpr_wdata_i,
  input  logic        dbg_gpr_we_i,

  // FPR writeback from WB
  input  logic        fp_wb_we_i,
  input  logic [4:0]  fp_wb_rd_addr_i,
  input  logic [63:0] fp_wb_data_i,

  // Debug abstract FPR access
  input  logic [4:0]  dbg_fpr_raddr_i,
  output logic [63:0] dbg_fpr_rdata_o,
  input  logic [4:0]  dbg_fpr_waddr_i,
  input  logic [63:0] dbg_fpr_wdata_i,
  input  logic        dbg_fpr_we_i,

  // Decode source-register metadata
  output logic [4:0]  src_rs1_addr_o,
  output logic [4:0]  src_rs2_addr_o,
  output logic        uses_rs1_o,
  output logic        uses_rs2_o,
  output logic        conditional_branch_o,
  output logic        store_instruction_o,

  // Decoded FPR source metadata for FP dependency interlocks
  output logic        uses_frs1_o,
  output logic        uses_frs2_o,
  output logic        uses_frs3_o,
  output logic [4:0]  src_frs1_addr_o,
  output logic [4:0]  src_frs2_addr_o,
  output logic [4:0]  src_frs3_addr_o,

  // BHT training from resolved EX branches
  input  logic        bht_update_valid_i,
  input  xlen_t       bht_update_pc_i,
  input  logic        bht_update_taken_i,

  // RAS maintenance from resolved EX jumps and returns
  input  logic        ras_push_valid_i,
  input  xlen_t       ras_push_addr_i,
  input  logic        ras_pop_valid_i,

  // ID-stage direct-control prediction
  input  logic        early_redirect_enable_i,
  output logic        predict_redirect_o,
  output xlen_t       predict_redirect_pc_o
);

  // Compressed-instruction normalization
  logic [31:0] decompressed_instr;
  logic        c_illegal;
  logic [31:0] decoded_instr;

  // ID-stage branch-prediction classification
  logic        direct_jump;
  logic        return_pred_valid;
  xlen_t       return_pred_target;
  logic        branch_pred_valid;
  logic        branch_pred_taken;
  logic        branch_pred_bht_used;

  // GPR/FPR read data and ID/EX packet construction
  xlen_t       rdata_a;
  xlen_t       rdata_b;
  logic [63:0] fdata_a;
  logic [63:0] fdata_b;
  logic [63:0] fdata_c;
  id_ex_t      id_ex_d;
  id_ex_t      id_ex_bypassed;

  // ---------------------------------------------------------------------------
  // Instruction normalization and source metadata
  // ---------------------------------------------------------------------------
  c_decompressor c_decomp_i (
    .c_instr_i (if_id_i.instr[15:0]),
    .instr_o   (decompressed_instr),
    .illegal_o (c_illegal)
  );

  assign decoded_instr = if_id_i.compressed ? decompressed_instr : if_id_i.instr;
  assign src_rs1_addr_o = decoded_instr[19:15];
  assign src_rs2_addr_o = decoded_instr[24:20];
  assign src_frs1_addr_o = decoded_instr[19:15];
  assign src_frs2_addr_o = decoded_instr[24:20];
  assign src_frs3_addr_o = decoded_instr[31:27];
  assign conditional_branch_o = (decoded_instr[6:0] == 7'b110_0011) &&
                                (decoded_instr[14:12] != 3'b010) &&
                                (decoded_instr[14:12] != 3'b011);
  assign store_instruction_o = (decoded_instr[6:0] == 7'b010_0011);
  // The predictor receives the raw halfword as well as the normalized form:
  // predictable C control instructions bypass the full decompressor on the
  // early redirect path. C.JALR remains EX-resolved because its target is
  // indirect.
  branch_predictor #(
    .ENABLE_BHT_P(ENABLE_BHT_P),
    .ENABLE_RAS_P(ENABLE_RAS_P)
  ) branch_predictor_i (
    // Clock and reset
    .clk                (clk),
    .rst_n              (rst_n),
    // Prediction eligibility
    // Redirect flushes kill this ID packet and take priority at IF, so they
    // need not suppress the combinational query. The core already removes
    // replay-stall conditions from early_redirect_enable_i.
    .enable_i           (early_redirect_enable_i),
    .valid_i            (if_id_i.valid),
    .illegal_i          (if_id_i.compressed && c_illegal),
    // Current normalized instruction
    .pc_i               (if_id_i.pc),
    .instr_i            (decoded_instr),
    .compressed_i       (if_id_i.compressed),
    .c_instr_i          (if_id_i.instr[15:0]),
    // Resolved-branch training
    .bht_update_valid_i (bht_update_valid_i),
    .bht_update_pc_i    (bht_update_pc_i),
    .bht_update_taken_i (bht_update_taken_i),
    // Resolved RAS maintenance
    .ras_push_valid_i   (ras_push_valid_i),
    .ras_push_addr_i    (ras_push_addr_i),
    .ras_pop_valid_i    (ras_pop_valid_i),
    // Redirect result
    .redirect_o         (predict_redirect_o),
    .redirect_pc_o      (predict_redirect_pc_o),
    // Prediction classification carried into EX
    .direct_jump_o      (direct_jump),
    .return_pred_valid_o(return_pred_valid),
    .return_pred_target_o(return_pred_target),
    .branch_pred_valid_o(branch_pred_valid),
    .branch_pred_taken_o(branch_pred_taken),
    .branch_pred_bht_used_o(branch_pred_bht_used)
  );

  // Source-use metadata feeds the core load-use interlock. Keep it adjacent to
  // the normalized instruction rather than duplicating decode in the core.
  always_comb begin
    uses_rs1_o = 1'b0;
    uses_rs2_o = 1'b0;
    uses_frs1_o = 1'b0;
    uses_frs2_o = 1'b0;
    uses_frs3_o = 1'b0;
    unique case (decoded_instr[6:0])
      7'b011_0011: begin // OP, including M-extension operations
        uses_rs1_o = 1'b1;
        uses_rs2_o = 1'b1;
      end
      7'b001_0011, // OP-IMM
      7'b000_0011, // LOAD
      7'b110_0111: begin // JALR
        uses_rs1_o = 1'b1;
      end
      7'b010_0011, // STORE
      7'b110_0011: begin // BRANCH
        uses_rs1_o = 1'b1;
        uses_rs2_o = 1'b1;
      end
      7'b111_0011: begin // CSR SYSTEM instructions using rs1
        uses_rs1_o = (decoded_instr[14:12] == 3'b001) ||
                     (decoded_instr[14:12] == 3'b010) ||
                     (decoded_instr[14:12] == 3'b011);
      end
      7'b010_0111: uses_frs2_o = 1'b1; // FSW
      7'b100_0011, 7'b100_0111, 7'b100_1011, 7'b100_1111: begin
        uses_frs1_o = 1'b1; uses_frs2_o = 1'b1; uses_frs3_o = 1'b1;
      end
      7'b101_0011: begin
        if (decoded_instr[31:25] == 7'b1101000 || decoded_instr[31:25] == 7'b1101001 ||
            decoded_instr[31:25] == 7'b1111000 || decoded_instr[31:25] == 7'b1111001)
          uses_rs1_o = 1'b1;
        if (decoded_instr[31:25] != 7'b1101000 && decoded_instr[31:25] != 7'b1101001 &&
            decoded_instr[31:25] != 7'b1111000 && decoded_instr[31:25] != 7'b1111001)
          uses_frs1_o = 1'b1;
        // Binary FP arithmetic, sign injection, min/max, and FEQ/FLT/FLE
        // all consume rs2 as an FPR source.
        if (decoded_instr[31:26] == 6'b000000 || decoded_instr[31:26] == 6'b000010 ||
            decoded_instr[31:26] == 6'b000100 || decoded_instr[31:26] == 6'b000110 ||
            decoded_instr[31:26] == 6'b001000 || decoded_instr[31:26] == 6'b001010 ||
            decoded_instr[31:26] == 6'b101000)
          uses_frs2_o = 1'b1;
      end
      default: begin end
    endcase
  end

  // ---------------------------------------------------------------------------
  // Register-file access and instruction decode
  // ---------------------------------------------------------------------------
  regfile regfile_i (
    .clk        (clk),
    .rst_n      (rst_n),
    .raddr_a_i  (decoded_instr[19:15]),
    .rdata_a_o  (rdata_a),
    .raddr_b_i  (decoded_instr[24:20]),
    .rdata_b_o  (rdata_b),
    .waddr_a_i  (wb_rd_addr_i),
    .wdata_a_i  (wb_rd_data_i),
    .we_a_i     (wb_we_i),
    .dbg_raddr_i(dbg_gpr_raddr_i),
    .dbg_rdata_o(dbg_gpr_rdata_o),
    .dbg_waddr_i(dbg_gpr_waddr_i),
    .dbg_wdata_i(dbg_gpr_wdata_i),
    .dbg_we_i   (dbg_gpr_we_i)
  );

  // FPR reads, WB writeback, and Debug abstract access stay local to ID.
  fp_regfile fp_regfile_i (
    .clk          (clk),
    .raddr_a_i    (decoded_instr[19:15]),
    .rdata_a_o    (fdata_a),
    .raddr_b_i    (decoded_instr[24:20]),
    .rdata_b_o    (fdata_b),
    .raddr_c_i    (decoded_instr[31:27]),
    .rdata_c_o    (fdata_c),
    .we_i         (fp_wb_we_i),
    .waddr_i      (fp_wb_rd_addr_i),
    .wdata_i      (fp_wb_data_i),
    .dbg_raddr_i  (dbg_fpr_raddr_i),
    .dbg_rdata_o  (dbg_fpr_rdata_o),
    .dbg_we_i     (dbg_fpr_we_i),
    .dbg_waddr_i  (dbg_fpr_waddr_i),
    .dbg_wdata_i  (dbg_fpr_wdata_i)
  );

  decoder decoder_i (
    .i_inst    (decoded_instr),
    .i_pc      (if_id_i.pc),
    .i_rdata_a (rdata_a),
    .i_rdata_b (rdata_b),
    .i_fdata_a (fdata_a),
    .i_fdata_b (fdata_b),
    .i_fdata_c (fdata_c),
    .i_valid   (if_id_i.valid),
    .o_id_ex   (id_ex_d)
  );

  // ---------------------------------------------------------------------------
  // ID/EX packet construction and registration
  // ---------------------------------------------------------------------------
  always_comb begin
    id_ex_bypassed = id_ex_d;
    id_ex_bypassed.compressed = if_id_i.compressed;
    id_ex_bypassed.jal_early = direct_jump;
    id_ex_bypassed.return_pred_valid = return_pred_valid;
    id_ex_bypassed.return_pred_target = return_pred_target;
    id_ex_bypassed.branch_pred_valid = branch_pred_valid;
    id_ex_bypassed.branch_pred_taken = branch_pred_taken;
    id_ex_bypassed.branch_pred_bht_used = branch_pred_bht_used;

    // Force illegal-instr when the C decompressor detects an illegal encoding.
    if (if_id_i.compressed && c_illegal) begin
      id_ex_bypassed.illegal_instr = 1'b1;
      // mtval for an illegal instruction reports the original encoding, not
      // the decompressor's harmless default instruction.
      id_ex_bypassed.instr = {16'h0000, if_id_i.instr[15:0]};
    end

    // Regfile write-through handles most same-cycle read/write cases, but the
    // staged MEM/WB handoff can still present a just-loaded value too late for
    // the decoder snapshot on this clock edge. Mirror the WB bypass here so the
    // ID/EX packet always captures the architecturally newest operands.
    if (wb_we_i && (wb_rd_addr_i != 5'd0) && (wb_rd_addr_i == id_ex_d.rs1_addr)) begin
      id_ex_bypassed.rs1_data = wb_rd_data_i;
    end
    if (wb_we_i && (wb_rd_addr_i != 5'd0) && (wb_rd_addr_i == id_ex_d.rs2_addr)) begin
      id_ex_bypassed.rs2_data = wb_rd_data_i;
    end
    if (fp_wb_we_i && (fp_wb_rd_addr_i == id_ex_d.fp_rs1_addr)) begin
      id_ex_bypassed.fp_rs1_data = fp_wb_data_i;
    end
    if (fp_wb_we_i && (fp_wb_rd_addr_i == id_ex_d.fp_rs2_addr)) begin
      id_ex_bypassed.fp_rs2_data = fp_wb_data_i;
    end
    if (fp_wb_we_i && (fp_wb_rd_addr_i == id_ex_d.fp_rs3_addr)) begin
      id_ex_bypassed.fp_rs3_data = fp_wb_data_i;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      id_ex_o <= '0;
    end else if (id_ex_flush_i) begin
      id_ex_o <= '0;
    end else if (id_ex_en_i) begin
      id_ex_o <= id_ex_bypassed;
    end else begin
      if (wb_we_i && (wb_rd_addr_i != 5'd0) && (wb_rd_addr_i == id_ex_o.rs1_addr)) begin
        id_ex_o.rs1_data <= wb_rd_data_i;
      end
      if (wb_we_i && (wb_rd_addr_i != 5'd0) && (wb_rd_addr_i == id_ex_o.rs2_addr)) begin
        id_ex_o.rs2_data <= wb_rd_data_i;
      end
    end
  end

endmodule
