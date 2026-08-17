// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Decode stage instruction parser.
// It expands one fetched instruction into the packed ID/EX control bundle.
module decoder
  import riscv_pkg::*;
(
  // Normalized instruction and PC
  input  logic [31:0] i_inst,
  input  xlen_t       i_pc,

  // GPR source read data
  input  xlen_t       i_rdata_a,
  input  xlen_t       i_rdata_b,

  // FPR source read data
  input  logic [63:0] i_fdata_a,
  input  logic [63:0] i_fdata_b,
  input  logic [63:0] i_fdata_c,
  input  logic        i_valid,
  output id_ex_t      o_id_ex
);

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;

  assign opcode = i_inst[6:0];
  assign funct3 = i_inst[14:12];
  assign funct7 = i_inst[31:25];

  always_comb begin
    o_id_ex = '0;
    o_id_ex.pc            = i_pc;
    o_id_ex.instr         = i_inst;
    o_id_ex.rs1_data      = i_rdata_a;
    o_id_ex.rs2_data      = i_rdata_b;
    o_id_ex.fp_rs1_data   = i_fdata_a;
    o_id_ex.fp_rs2_data   = i_fdata_b;
    o_id_ex.fp_rs3_data   = i_fdata_c;
    o_id_ex.fp_rs1_addr   = i_inst[19:15];
    o_id_ex.fp_rs2_addr   = i_inst[24:20];
    o_id_ex.fp_rs3_addr   = i_inst[31:27];
    o_id_ex.rs1_addr      = i_inst[19:15];
    o_id_ex.rs2_addr      = i_inst[24:20];
    o_id_ex.rd_addr       = i_inst[11:7];
    o_id_ex.csr_addr      = i_inst[31:20];
    o_id_ex.op_a_sel      = OP_A_RS1;
    o_id_ex.op_b_sel      = OP_B_RS2;
    o_id_ex.alu_op        = ALU_ADD;
    o_id_ex.wb_sel        = WB_ALU;
    o_id_ex.illegal_instr = i_valid;

    unique case (opcode)
      7'b000_1111: begin
        // Both fence forms drain the D-side memory system. FENCE.I
        // additionally asks the core to discard any prefetched instruction
        // and refetch after the fence.
        if (funct3 == 3'b000 || funct3 == 3'b001) begin
          o_id_ex.valid         = i_valid;
          o_id_ex.illegal_instr = 1'b0;
          o_id_ex.fence         = 1'b1;
          o_id_ex.fence_i       = (funct3 == 3'b001);
        end else if (HAS_ZICBOM && funct3 == 3'b010 &&
                     i_inst[11:7] == 5'd0) begin
          unique case (i_inst[31:20])
            12'h000: o_id_ex.cbo_op = CBO_INVAL;
            12'h001: o_id_ex.cbo_op = CBO_CLEAN;
            12'h002: o_id_ex.cbo_op = CBO_FLUSH;
            default: ;
          endcase
          if (o_id_ex.cbo_op != CBO_NONE) begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
          end
        end
      end
      7'b011_0111: begin // LUI
        o_id_ex.valid         = i_valid;
        o_id_ex.illegal_instr = 1'b0;
        o_id_ex.imm           = {{(CORE_XLEN-32){i_inst[31]}}, i_inst[31:12], 12'h000};
        o_id_ex.op_a_sel      = OP_A_ZERO;
        o_id_ex.op_b_sel      = OP_B_IMM;
        o_id_ex.rd_we         = 1'b1;
      end
      7'b001_0111: begin // AUIPC
        o_id_ex.valid         = i_valid;
        o_id_ex.illegal_instr = 1'b0;
        o_id_ex.imm           = {{(CORE_XLEN-32){i_inst[31]}}, i_inst[31:12], 12'h000};
        o_id_ex.op_a_sel      = OP_A_PC;
        o_id_ex.op_b_sel      = OP_B_IMM;
        o_id_ex.rd_we         = 1'b1;
      end
      7'b001_0011: begin // OP-IMM
        o_id_ex.imm      = {{(CORE_XLEN-12){i_inst[31]}}, i_inst[31:20]};
        o_id_ex.op_b_sel = OP_B_IMM;
        unique case (funct3)
          3'b000: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_ADD;
            o_id_ex.rd_we         = 1'b1;
          end
          3'b010: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_SLT;
            o_id_ex.rd_we         = 1'b1;
          end
          3'b011: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_SLTU;
            o_id_ex.rd_we         = 1'b1;
          end
          3'b100: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_XOR;
            o_id_ex.rd_we         = 1'b1;
          end
          3'b110: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_OR;
            o_id_ex.rd_we         = 1'b1;
          end
          3'b111: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_AND;
            o_id_ex.rd_we         = 1'b1;
          end
          3'b001: begin
            // RV64 SLLI carries shamt[5] in bit 25, so only funct6 is
            // fixed.  Matching funct7 would incorrectly reject shifts 32..63.
            if (i_inst[31:26] == 6'b000_000) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.alu_op        = ALU_SLL;
              o_id_ex.rd_we         = 1'b1;
            end
          end
          3'b101: begin
            // RV64 SRLI/SRAI likewise use a six-bit shift amount.
            if (i_inst[31:26] == 6'b000_000) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.alu_op        = ALU_SRL;
              o_id_ex.rd_we         = 1'b1;
            end else if (i_inst[31:26] == 6'b010_000) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.alu_op        = ALU_SRA;
              o_id_ex.rd_we         = 1'b1;
            end
          end
          default: begin
          end
        endcase
      end
      7'b001_1011: begin // OP-IMM-32
        o_id_ex.word_op  = 1'b1;
        o_id_ex.op_b_sel = OP_B_IMM;
        unique case (funct3)
          3'b000: begin // ADDIW
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.imm = {{(CORE_XLEN-12){i_inst[31]}}, i_inst[31:20]};
            o_id_ex.alu_op = ALU_ADDW; o_id_ex.rd_we = 1'b1;
          end
          3'b001: begin // SLLIW
            if (funct7 == 7'b0000000) begin
              o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
              o_id_ex.imm = {59'd0, i_inst[24:20]};
              o_id_ex.alu_op = ALU_SLLW; o_id_ex.rd_we = 1'b1;
            end
          end
          3'b101: begin // SRLIW/SRAIW
            if (funct7 == 7'b0000000 || funct7 == 7'b0100000) begin
              o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
              o_id_ex.imm = {59'd0, i_inst[24:20]};
              o_id_ex.alu_op = (funct7 == 7'b0000000) ? ALU_SRLW : ALU_SRAW;
              o_id_ex.rd_we = 1'b1;
            end
          end
          default: begin end
        endcase
      end
      7'b011_0011: begin // OP
        unique case ({funct7, funct3})
          {7'b000_0000, 3'b000}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_ADD;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b010_0000, 3'b000}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_SUB;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b000_0000, 3'b001}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_SLL;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b000_0000, 3'b010}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_SLT;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b000_0000, 3'b011}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_SLTU;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b000_0000, 3'b100}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_XOR;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b000_0000, 3'b101}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_SRL;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b010_0000, 3'b101}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_SRA;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b000_0000, 3'b110}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_OR;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b000_0000, 3'b111}: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.alu_op        = ALU_AND;
            o_id_ex.rd_we         = 1'b1;
          end
          {7'b000_0001, 3'b000}: begin
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.rd_we = 1'b1; o_id_ex.muldiv_en = 1'b1; o_id_ex.muldiv_op = MULDIV_MUL;
          end
          {7'b000_0001, 3'b001}: begin
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.rd_we = 1'b1; o_id_ex.muldiv_en = 1'b1; o_id_ex.muldiv_op = MULDIV_MULH;
          end
          {7'b000_0001, 3'b010}: begin
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.rd_we = 1'b1; o_id_ex.muldiv_en = 1'b1; o_id_ex.muldiv_op = MULDIV_MULHSU;
          end
          {7'b000_0001, 3'b011}: begin
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.rd_we = 1'b1; o_id_ex.muldiv_en = 1'b1; o_id_ex.muldiv_op = MULDIV_MULHU;
          end
          {7'b000_0001, 3'b100}: begin
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.rd_we = 1'b1; o_id_ex.muldiv_en = 1'b1; o_id_ex.muldiv_op = MULDIV_DIV;
          end
          {7'b000_0001, 3'b101}: begin
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.rd_we = 1'b1; o_id_ex.muldiv_en = 1'b1; o_id_ex.muldiv_op = MULDIV_DIVU;
          end
          {7'b000_0001, 3'b110}: begin
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.rd_we = 1'b1; o_id_ex.muldiv_en = 1'b1; o_id_ex.muldiv_op = MULDIV_REM;
          end
          {7'b000_0001, 3'b111}: begin
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.rd_we = 1'b1; o_id_ex.muldiv_en = 1'b1; o_id_ex.muldiv_op = MULDIV_REMU;
          end
          default: begin
          end
        endcase
      end
      7'b011_1011: begin // OP-32
        o_id_ex.word_op = 1'b1;
        unique case ({funct7, funct3})
          {7'b0000000, 3'b000}: begin o_id_ex.alu_op = ALU_ADDW; o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0; o_id_ex.rd_we = 1'b1; end
          {7'b0100000, 3'b000}: begin o_id_ex.alu_op = ALU_SUBW; o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0; o_id_ex.rd_we = 1'b1; end
          {7'b0000000, 3'b001}: begin o_id_ex.alu_op = ALU_SLLW; o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0; o_id_ex.rd_we = 1'b1; end
          {7'b0000000, 3'b101}: begin o_id_ex.alu_op = ALU_SRLW; o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0; o_id_ex.rd_we = 1'b1; end
          {7'b0100000, 3'b101}: begin o_id_ex.alu_op = ALU_SRAW; o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0; o_id_ex.rd_we = 1'b1; end
          {7'b0000001, 3'b000}: begin o_id_ex.muldiv_op = MULDIV_MUL;  o_id_ex.muldiv_en = 1'b1; o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0; o_id_ex.rd_we = 1'b1; end
          {7'b0000001, 3'b100}: begin o_id_ex.muldiv_op = MULDIV_DIV;  o_id_ex.muldiv_en = 1'b1; o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0; o_id_ex.rd_we = 1'b1; end
          {7'b0000001, 3'b101}: begin o_id_ex.muldiv_op = MULDIV_DIVU; o_id_ex.muldiv_en = 1'b1; o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0; o_id_ex.rd_we = 1'b1; end
          {7'b0000001, 3'b110}: begin o_id_ex.muldiv_op = MULDIV_REM;  o_id_ex.muldiv_en = 1'b1; o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0; o_id_ex.rd_we = 1'b1; end
          {7'b0000001, 3'b111}: begin o_id_ex.muldiv_op = MULDIV_REMU; o_id_ex.muldiv_en = 1'b1; o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0; o_id_ex.rd_we = 1'b1; end
          default: begin end
        endcase
      end
      7'b000_0011: begin // LOAD
        o_id_ex.imm      = {{(CORE_XLEN-12){i_inst[31]}}, i_inst[31:20]};
        o_id_ex.op_a_sel = OP_A_RS1;
        o_id_ex.op_b_sel = OP_B_IMM;
        o_id_ex.alu_op   = ALU_ADD;
        o_id_ex.mem_load = 1'b1;
        o_id_ex.mem_type = funct3;
        o_id_ex.rd_we    = 1'b1;
        o_id_ex.wb_sel   = WB_MEM;
        unique case (funct3)
          3'b000, 3'b001, 3'b010, 3'b011, 3'b100, 3'b101, 3'b110: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
          end
          default: begin
          end
        endcase
      end
      7'b010_0011: begin // STORE
        o_id_ex.imm       = {{(CORE_XLEN-12){i_inst[31]}}, i_inst[31:25], i_inst[11:7]};
        o_id_ex.op_a_sel  = OP_A_RS1;
        o_id_ex.op_b_sel  = OP_B_IMM;
        o_id_ex.alu_op    = ALU_ADD;
        o_id_ex.mem_store = 1'b1;
        o_id_ex.mem_type  = funct3;
        unique case (funct3)
          3'b000, 3'b001, 3'b010, 3'b011: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
          end
          default: begin
          end
        endcase
      end
      7'b010_1111: begin // RV64A: LR/SC and AMO.W/AMO.D
        // AMOs use rs1 directly as their effective address.  LR requires an
        // all-zero rs2 encoding; every AMO returns its old value through the
        // ordinary MEM writeback path, while SC returns its success code.
        o_id_ex.op_a_sel = OP_A_RS1;
        o_id_ex.op_b_sel = OP_B_IMM;
        o_id_ex.alu_op   = ALU_ADD;
        o_id_ex.mem_load = 1'b1;
        o_id_ex.mem_type = funct3;
        o_id_ex.rd_we    = 1'b1;
        o_id_ex.wb_sel   = WB_MEM;
        o_id_ex.atomic_aq = i_inst[26];
        o_id_ex.atomic_rl = i_inst[25];
        if (funct3 == 3'b010 || funct3 == 3'b011) begin
          unique case (i_inst[31:27])
            5'b00010: begin // LR.W / LR.D
              if (i_inst[24:20] == 5'd0) begin
                o_id_ex.valid         = i_valid;
                o_id_ex.illegal_instr = 1'b0;
                o_id_ex.atomic_op     = ATOMIC_LR;
              end
            end
            5'b00011: begin o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0; o_id_ex.atomic_op = ATOMIC_SC;   end
            5'b00001: begin o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0; o_id_ex.atomic_op = ATOMIC_SWAP; end
            5'b00000: begin o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0; o_id_ex.atomic_op = ATOMIC_ADD;  end
            5'b00100: begin o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0; o_id_ex.atomic_op = ATOMIC_XOR;  end
            5'b01100: begin o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0; o_id_ex.atomic_op = ATOMIC_AND;  end
            5'b01000: begin o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0; o_id_ex.atomic_op = ATOMIC_OR;   end
            5'b10000: begin o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0; o_id_ex.atomic_op = ATOMIC_MIN;  end
            5'b10100: begin o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0; o_id_ex.atomic_op = ATOMIC_MAX;  end
            5'b11000: begin o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0; o_id_ex.atomic_op = ATOMIC_MINU; end
            5'b11100: begin o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0; o_id_ex.atomic_op = ATOMIC_MAXU; end
            default: begin end
          endcase
        end
      end
      7'b000_0111: begin // FLW / FLD
        if (funct3 == 3'b010 || funct3 == 3'b011) begin
          o_id_ex.valid         = i_valid;
          o_id_ex.illegal_instr = 1'b0;
          o_id_ex.imm           = {{(CORE_XLEN-12){i_inst[31]}}, i_inst[31:20]};
          o_id_ex.op_a_sel      = OP_A_RS1;
          o_id_ex.op_b_sel      = OP_B_IMM;
          o_id_ex.alu_op        = ALU_ADD;
          o_id_ex.mem_load      = 1'b1;
          o_id_ex.mem_type      = funct3;
          o_id_ex.fp_write      = 1'b1;
          o_id_ex.fp_access     = 1'b1;
          o_id_ex.fp_dst_fmt    = funct3 == 3'b011 ? FP_FMT_D : FP_FMT_S;
        end
      end
      7'b010_0111: begin // FSW / FSD
        if (funct3 == 3'b010 || funct3 == 3'b011) begin
          o_id_ex.valid         = i_valid;
          o_id_ex.illegal_instr = 1'b0;
          o_id_ex.imm           = {{(CORE_XLEN-12){i_inst[31]}}, i_inst[31:25], i_inst[11:7]};
          o_id_ex.op_a_sel      = OP_A_RS1;
          o_id_ex.op_b_sel      = OP_B_IMM;
          o_id_ex.alu_op        = ALU_ADD;
          o_id_ex.mem_store     = 1'b1;
          o_id_ex.mem_type      = funct3;
          o_id_ex.fp_rs2_data   = i_fdata_b;
          o_id_ex.fp_access     = 1'b1;
          o_id_ex.fp_src_fmt    = funct3 == 3'b011 ? FP_FMT_D : FP_FMT_S;
        end
      end
      7'b100_0011, 7'b100_0111, 7'b100_1011, 7'b100_1111: begin // FMADD.S/D family
        if (i_inst[26:25] == 2'b00 || i_inst[26:25] == 2'b01) begin
          o_id_ex.valid                 = i_valid;
          o_id_ex.illegal_instr         = 1'b0;
          o_id_ex.fp_op                 = 1'b1;
          o_id_ex.fp_access             = 1'b1;
          o_id_ex.fp_write              = 1'b1;
          o_id_ex.fp_rounding_mode      = funct3;
          o_id_ex.fp_rounding_dynamic   = (funct3 == 3'b111);
          o_id_ex.fp_src_fmt            = i_inst[25] ? FP_FMT_D : FP_FMT_S;
          o_id_ex.fp_dst_fmt            = i_inst[25] ? FP_FMT_D : FP_FMT_S;
          o_id_ex.fp_operation          = (opcode == 7'b100_0011 || opcode == 7'b100_0111) ? FP_OP_FMADD : FP_OP_FNMSUB;
          // CVFPU's FNMSUB operation with op_mod=0 computes -A*B+C;
          // RISC-V FNMSUB requires -A*B-C, while FNMADD requires -A*B+C.
          o_id_ex.fp_operation_modifier = (opcode == 7'b100_0111 || opcode == 7'b100_1011);
        end
      end
      7'b101_0011: begin // OP-FP
        o_id_ex.fp_rounding_mode    = funct3;
        o_id_ex.fp_rounding_dynamic = (funct3 == 3'b111);
        unique case (funct7)
          7'b0000000, 7'b0000001, 7'b0000100, 7'b0000101: begin // FADD.S/D / FSUB.S/D
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.fp_op = 1'b1; o_id_ex.fp_access = 1'b1; o_id_ex.fp_write = 1'b1;
            o_id_ex.fp_operation = FP_OP_ADD;
            o_id_ex.fp_operation_modifier = (funct7[6:1] == 6'b000010);
            o_id_ex.fp_src_fmt = funct7[0] ? FP_FMT_D : FP_FMT_S;
            o_id_ex.fp_dst_fmt = funct7[0] ? FP_FMT_D : FP_FMT_S;
          end
          7'b0001000, 7'b0001001: begin // FMUL.S/D
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.fp_op = 1'b1; o_id_ex.fp_access = 1'b1; o_id_ex.fp_write = 1'b1; o_id_ex.fp_operation = FP_OP_MUL;
            o_id_ex.fp_src_fmt = funct7[0] ? FP_FMT_D : FP_FMT_S;
            o_id_ex.fp_dst_fmt = funct7[0] ? FP_FMT_D : FP_FMT_S;
          end
          7'b0001100, 7'b0001101: begin // FDIV.S/D
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.fp_op = 1'b1; o_id_ex.fp_access = 1'b1; o_id_ex.fp_write = 1'b1; o_id_ex.fp_operation = FP_OP_DIV;
            o_id_ex.fp_src_fmt = funct7[0] ? FP_FMT_D : FP_FMT_S;
            o_id_ex.fp_dst_fmt = funct7[0] ? FP_FMT_D : FP_FMT_S;
          end
          7'b0101100, 7'b0101101: begin // FSQRT.S/D
            if (i_inst[24:20] == 5'd0) begin
              o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
              o_id_ex.fp_op = 1'b1; o_id_ex.fp_access = 1'b1; o_id_ex.fp_write = 1'b1; o_id_ex.fp_operation = FP_OP_SQRT;
              o_id_ex.fp_src_fmt = funct7[0] ? FP_FMT_D : FP_FMT_S;
              o_id_ex.fp_dst_fmt = funct7[0] ? FP_FMT_D : FP_FMT_S;
            end
          end
          7'b0010000, 7'b0010001: begin // FSGNJ*.S/D
            o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
            o_id_ex.fp_op = 1'b1; o_id_ex.fp_access = 1'b1; o_id_ex.fp_write = 1'b1; o_id_ex.fp_operation = FP_OP_SGNJ;
            o_id_ex.fp_src_fmt = funct7[0] ? FP_FMT_D : FP_FMT_S;
            o_id_ex.fp_dst_fmt = funct7[0] ? FP_FMT_D : FP_FMT_S;
          end
          7'b0010100, 7'b0010101: begin // FMIN/FMAX.S/D
            if (funct3 <= 3'b001) begin
              o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
              o_id_ex.fp_op = 1'b1; o_id_ex.fp_access = 1'b1; o_id_ex.fp_write = 1'b1; o_id_ex.fp_operation = FP_OP_MINMAX;
              o_id_ex.fp_operation_modifier = funct3[0];
              o_id_ex.fp_src_fmt = funct7[0] ? FP_FMT_D : FP_FMT_S;
              o_id_ex.fp_dst_fmt = funct7[0] ? FP_FMT_D : FP_FMT_S;
            end
          end
          7'b1010000, 7'b1010001: begin // FEQ/FLT/FLE.S/D
            if (funct3 == 3'b010 || funct3 == 3'b001 || funct3 == 3'b000) begin
              o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
              o_id_ex.fp_op = 1'b1; o_id_ex.fp_access = 1'b1; o_id_ex.rd_we = 1'b1; o_id_ex.fp_operation = FP_OP_CMP;
              o_id_ex.fp_operation_modifier = 1'b0;
              o_id_ex.fp_src_fmt = funct7[0] ? FP_FMT_D : FP_FMT_S;
              o_id_ex.fp_dst_fmt = funct7[0] ? FP_FMT_D : FP_FMT_S;
            end
          end
          7'b1110000, 7'b1110001: begin // FMV.X.W/D / FCLASS.S/D
            if (i_inst[24:20] == 5'd0 && (funct3 == 3'b000 || funct3 == 3'b001)) begin
              o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
              o_id_ex.fp_op = 1'b1; o_id_ex.fp_access = 1'b1; o_id_ex.rd_we = 1'b1;
              o_id_ex.fp_operation = (funct3 == 3'b000) ? FP_OP_SGNJ : FP_OP_CLASSIFY;
              o_id_ex.fp_operation_modifier = (funct3 == 3'b000);
              if (funct3 == 3'b000) o_id_ex.fp_rs2_data = i_fdata_a;
              o_id_ex.fp_src_fmt = funct7[0] ? FP_FMT_D : FP_FMT_S;
              o_id_ex.fp_dst_fmt = funct7[0] ? FP_FMT_D : FP_FMT_S;
              o_id_ex.fp_result_word = (funct3 == 3'b000) && !funct7[0];
            end
          end
          7'b1100000, 7'b1100001: begin // FCVT.W[U]/L[U].S/D
            if (i_inst[24:20] <= 5'd3) begin
              o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
              o_id_ex.fp_op = 1'b1; o_id_ex.fp_access = 1'b1; o_id_ex.rd_we = 1'b1; o_id_ex.fp_operation = FP_OP_F2I;
              o_id_ex.fp_operation_modifier = i_inst[20];
              o_id_ex.fp_src_fmt = funct7[0] ? FP_FMT_D : FP_FMT_S;
              o_id_ex.fp_int_fmt_d = i_inst[21];
              o_id_ex.fp_result_word = !i_inst[21];
            end
          end
          7'b1101000, 7'b1101001: begin // FCVT.S/D.W[U]/L[U]
            if (i_inst[24:20] <= 5'd3) begin
              o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
              o_id_ex.fp_op = 1'b1; o_id_ex.fp_access = 1'b1; o_id_ex.fp_write = 1'b1; o_id_ex.fp_operation = FP_OP_I2F;
              o_id_ex.fp_operation_modifier = i_inst[20];
              o_id_ex.fp_dst_fmt = funct7[0] ? FP_FMT_D : FP_FMT_S;
              o_id_ex.fp_int_fmt_d = i_inst[21];
              o_id_ex.fp_rs1_data = i_rdata_a;
            end
          end
          7'b0100000: begin // FCVT.S.D
            if (i_inst[24:20] == 5'd1) begin
              o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
              o_id_ex.fp_op = 1'b1; o_id_ex.fp_access = 1'b1; o_id_ex.fp_write = 1'b1;
              o_id_ex.fp_operation = FP_OP_F2F; o_id_ex.fp_src_fmt = FP_FMT_D;
              o_id_ex.fp_dst_fmt = FP_FMT_S;
            end
          end
          7'b0100001: begin // FCVT.D.S
            if (i_inst[24:20] == 5'd0) begin
              o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
              o_id_ex.fp_op = 1'b1; o_id_ex.fp_access = 1'b1; o_id_ex.fp_write = 1'b1;
              o_id_ex.fp_operation = FP_OP_F2F; o_id_ex.fp_src_fmt = FP_FMT_S;
              o_id_ex.fp_dst_fmt = FP_FMT_D;
            end
          end
          7'b1111000, 7'b1111001: begin // FMV.W.X / FMV.D.X
            if (i_inst[24:20] == 5'd0 && funct3 == 3'b000) begin
              o_id_ex.valid = i_valid; o_id_ex.illegal_instr = 1'b0;
              o_id_ex.fp_op = 1'b1; o_id_ex.fp_access = 1'b1; o_id_ex.fp_write = 1'b1; o_id_ex.fp_operation = FP_OP_SGNJ;
              o_id_ex.fp_operation_modifier = 1'b1; o_id_ex.fp_rs1_data = i_rdata_a;
              o_id_ex.fp_rs2_data = i_rdata_a;
              o_id_ex.fp_src_fmt = funct7[0] ? FP_FMT_D : FP_FMT_S;
              o_id_ex.fp_dst_fmt = funct7[0] ? FP_FMT_D : FP_FMT_S;
            end
          end
          default: begin end
        endcase
      end
      7'b110_0011: begin // BRANCH
        o_id_ex.imm = {{(CORE_XLEN-13){i_inst[31]}}, i_inst[31], i_inst[7], i_inst[30:25], i_inst[11:8], 1'b0};
        unique case (funct3)
          3'b000: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.branch_op     = BR_EQ;
          end
          3'b001: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.branch_op     = BR_NE;
          end
          3'b100: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.branch_op     = BR_LT;
          end
          3'b101: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.branch_op     = BR_GE;
          end
          3'b110: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.branch_op     = BR_LTU;
          end
          3'b111: begin
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.branch_op     = BR_GEU;
          end
          default: begin
          end
        endcase
      end
      7'b110_1111: begin // JAL
        o_id_ex.valid         = i_valid;
        o_id_ex.illegal_instr = 1'b0;
        o_id_ex.imm           = {{(CORE_XLEN-21){i_inst[31]}}, i_inst[31], i_inst[19:12], i_inst[20], i_inst[30:21], 1'b0};
        o_id_ex.op_a_sel      = OP_A_PC;
        o_id_ex.op_b_sel      = OP_B_FOUR;
        o_id_ex.jump_op       = JUMP_JAL;
        o_id_ex.rd_we         = 1'b1;
      end
      7'b110_0111: begin // JALR
        if (funct3 == 3'b000) begin
          o_id_ex.valid         = i_valid;
          o_id_ex.illegal_instr = 1'b0;
          o_id_ex.imm           = {{(CORE_XLEN-12){i_inst[31]}}, i_inst[31:20]};
          o_id_ex.op_a_sel      = OP_A_PC;
          o_id_ex.op_b_sel      = OP_B_FOUR;
          o_id_ex.jump_op       = JUMP_JALR;
          o_id_ex.rd_we         = 1'b1;
        end
      end
      7'b111_0011: begin // SYSTEM — CSR, ECALL/EBREAK, MRET, DRET
        // funct3 selects the sub-opcode:
        //   000 = privileged (ECALL/EBREAK/MRET/DRET based on imm[11:0])
        //   001 = CSRRW    (CSR Read-Write)
        //   010 = CSRRS    (CSR Read & Set bits)
        //   011 = CSRRC    (CSR Read & Clear bits)
        //   101 = CSRRWI   (CSR Read-Write Immediate)
        //   110 = CSRRSI   (CSR Read & Set bits Immediate)
        //   111 = CSRRCI   (CSR Read & Clear bits Immediate)
        o_id_ex.csr_addr = i_inst[31:20];
        unique case (funct3)
          3'b000: begin
            if (i_inst[31:20] == 12'h000) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.sys_op        = SYS_ECALL;
            end else if (i_inst[31:20] == 12'h001) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.sys_op        = SYS_EBREAK;
            end else if (i_inst[31:20] == 12'h302) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.sys_op        = SYS_MRET;
            end else if (i_inst[31:20] == 12'h102) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.sys_op        = SYS_SRET;
            end else if (i_inst[31:20] == 12'h105) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.sys_op        = SYS_WFI;
            end else if ((i_inst[31:25] == 7'b0001001) && (i_inst[11:7] == 5'd0)) begin
              // SFENCE.VMA rs1,rs2; the retired source values select the
              // local TLB entries to invalidate (zero denotes wildcard).
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.sys_op        = SYS_SFENCE_VMA;
            end else if (i_inst[31:20] == 12'h7b2) begin
              o_id_ex.valid         = i_valid;
              o_id_ex.illegal_instr = 1'b0;
              o_id_ex.sys_op        = SYS_DRET;
            end
          end
          3'b001: begin // CSRRW
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.csr_access    = 1'b1;
            o_id_ex.csr_op        = CSR_OP_WRITE;
            o_id_ex.rd_we         = 1'b1;
            o_id_ex.wb_sel        = WB_CSR;
          end
          3'b010: begin // CSRRS
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.csr_access    = 1'b1;
            o_id_ex.csr_op        = CSR_OP_SET;
            o_id_ex.rd_we         = 1'b1;
            o_id_ex.wb_sel        = WB_CSR;
          end
          3'b011: begin // CSRRC
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.csr_access    = 1'b1;
            o_id_ex.csr_op        = CSR_OP_CLEAR;
            o_id_ex.rd_we         = 1'b1;
            o_id_ex.wb_sel        = WB_CSR;
          end
          3'b101: begin // CSRRWI
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.csr_access    = 1'b1;
            o_id_ex.csr_use_imm   = 1'b1;
            o_id_ex.csr_imm       = i_inst[19:15];
            o_id_ex.csr_op        = CSR_OP_WRITE;
            o_id_ex.rd_we         = 1'b1;
            o_id_ex.wb_sel        = WB_CSR;
          end
          3'b110: begin // CSRRSI
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.csr_access    = 1'b1;
            o_id_ex.csr_use_imm   = 1'b1;
            o_id_ex.csr_imm       = i_inst[19:15];
            o_id_ex.csr_op        = CSR_OP_SET;
            o_id_ex.rd_we         = 1'b1;
            o_id_ex.wb_sel        = WB_CSR;
          end
          3'b111: begin // CSRRCI
            o_id_ex.valid         = i_valid;
            o_id_ex.illegal_instr = 1'b0;
            o_id_ex.csr_access    = 1'b1;
            o_id_ex.csr_use_imm   = 1'b1;
            o_id_ex.csr_imm       = i_inst[19:15];
            o_id_ex.csr_op        = CSR_OP_CLEAR;
            o_id_ex.rd_we         = 1'b1;
            o_id_ex.wb_sel        = WB_CSR;
          end
          default: begin
          end
        endcase
      end
      default: begin
      end
    endcase
  end

endmodule
