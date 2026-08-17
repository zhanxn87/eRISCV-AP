// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// XLEN-parameterized integer ALU.  RV64 shifts consume six bits; the decoder
// selects the sign-extending *W operations before this stage.
module alu #(
  parameter int unsigned XLEN_P = riscv_pkg::CORE_XLEN
) (
  input  riscv_pkg::alu_op_e i_alu_op,
  input  logic [XLEN_P-1:0]  i_operand_a,
  input  logic [XLEN_P-1:0]  i_operand_b,
  output logic [XLEN_P-1:0]  o_result
);
  import riscv_pkg::*;
  localparam int unsigned SHIFT_W = $clog2(XLEN_P);
  logic [31:0] word_result;

  always_comb begin
    unique case (i_alu_op)
      ALU_ADDW: word_result = i_operand_a[31:0] + i_operand_b[31:0];
      ALU_SUBW: word_result = i_operand_a[31:0] - i_operand_b[31:0];
      ALU_SLLW: word_result = i_operand_a[31:0] << i_operand_b[4:0];
      ALU_SRLW: word_result = i_operand_a[31:0] >> i_operand_b[4:0];
      ALU_SRAW: word_result = $signed(i_operand_a[31:0]) >>> i_operand_b[4:0];
      default: word_result = '0;
    endcase
  end

  always_comb begin
    unique case (i_alu_op)
      ALU_ADD:  o_result = i_operand_a + i_operand_b;
      ALU_SUB:  o_result = i_operand_a - i_operand_b;
      ALU_SLL:  o_result = i_operand_a << i_operand_b[SHIFT_W-1:0];
      ALU_SLT:  o_result = {{(XLEN_P-1){1'b0}}, ($signed(i_operand_a) < $signed(i_operand_b))};
      ALU_SLTU: o_result = {{(XLEN_P-1){1'b0}}, (i_operand_a < i_operand_b)};
      ALU_XOR:  o_result = i_operand_a ^ i_operand_b;
      ALU_SRL:  o_result = i_operand_a >> i_operand_b[SHIFT_W-1:0];
      ALU_SRA:  o_result = $signed(i_operand_a) >>> i_operand_b[SHIFT_W-1:0];
      ALU_OR:   o_result = i_operand_a | i_operand_b;
      ALU_AND:  o_result = i_operand_a & i_operand_b;
      ALU_ADDW, ALU_SUBW, ALU_SLLW, ALU_SRLW, ALU_SRAW:
        o_result = {{(XLEN_P-32){word_result[31]}}, word_result};
      default: o_result = i_operand_a + i_operand_b;
    endcase
  end
endmodule
