// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

import riscv_pkg::*;

// Iterative RV64M execution unit. word_op_i selects the RV64 *W variants;
// operands are normalized to 32 bits before execution and results sign extend.
module muldiv_unit #(
  parameter int unsigned XLEN_P = CORE_XLEN,
  parameter int unsigned MUL_ITER_BITS = 8,
  parameter bit          MUL_RESULT_REGISTER = 1'b1
) (
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 start_i,
  input  muldiv_op_e           op_i,
  input  logic                 word_op_i,
  input  logic [XLEN_P-1:0]    operand_a_i,
  input  logic [XLEN_P-1:0]    operand_b_i,
  output logic                 busy_o,
  output logic                 done_o,
  output logic [XLEN_P-1:0]    result_o
);

  localparam int unsigned COUNT_W = (XLEN_P > 1) ? $clog2(XLEN_P) : 1;
  localparam int unsigned MUL_ITER_CYCLES = XLEN_P / MUL_ITER_BITS;
  localparam logic [COUNT_W-1:0] MUL_ITER_LAST = COUNT_W'(MUL_ITER_CYCLES - 1);
  localparam logic [2:0] S_IDLE       = 3'd0;
  localparam logic [2:0] S_MUL        = 3'd1;
  localparam logic [2:0] S_DIV        = 3'd2;
  localparam logic [2:0] S_SPECIAL    = 3'd3;
  localparam logic [2:0] S_MUL_RESULT = 3'd4;

  generate
    if ((MUL_ITER_BITS != 1) && (MUL_ITER_BITS != 2) &&
        (MUL_ITER_BITS != 4) && (MUL_ITER_BITS != 8) &&
        (MUL_ITER_BITS != 16) && (MUL_ITER_BITS != 32) &&
        (MUL_ITER_BITS != 64)) begin : g_invalid_mul_iter_bits
      initial $fatal(1, "MUL_ITER_BITS must be 1, 2, 4, 8, 16, 32, or 64");
    end
    if ((MUL_ITER_BITS > XLEN_P) || ((XLEN_P % MUL_ITER_BITS) != 0)) begin : g_invalid_mul_width
      initial $fatal(1, "MUL_ITER_BITS must divide XLEN_P");
    end
  endgenerate

  logic [2:0] state_q;
  muldiv_op_e op_q;
  logic [COUNT_W-1:0] count_q;
  logic word_op_q;

  logic [2*XLEN_P-1:0] mul_acc_q;
  logic [2*XLEN_P-1:0] mul_multiplicand_q;
  logic [XLEN_P-1:0]   mul_multiplier_q;
  logic                 mul_negative_q;
  logic [XLEN_P-1:0]   mul_result_pending_q;

  logic [XLEN_P:0]     div_rem_q;
  logic [XLEN_P-1:0]   div_dividend_q;
  logic [XLEN_P-1:0]   div_divisor_q;
  logic [XLEN_P-1:0]   div_quotient_q;
  logic                 div_negative_quotient_q;
  logic                 div_negative_remainder_q;
  logic                 div_return_remainder_q;

  logic                 mul_signed_a;
  logic                 mul_signed_b;
  logic                 div_signed;
  logic [XLEN_P-1:0]   operand_a_normalized;
  logic [XLEN_P-1:0]   operand_b_normalized;
  logic [XLEN_P-1:0]   start_abs_a;
  logic [XLEN_P-1:0]   start_abs_b;
  logic [2*XLEN_P-1:0] mul_partial;
  logic [2*XLEN_P-1:0] mul_acc_next;
  logic [2*XLEN_P-1:0] mul_product_next;
  logic [XLEN_P:0]     div_shifted_rem;
  logic                 div_ge;
  logic [XLEN_P:0]     div_rem_next;
  logic [XLEN_P-1:0]   div_dividend_next;
  logic [XLEN_P-1:0]   div_quotient_next;
  logic [XLEN_P-1:0]   div_quotient_signed;
  logic [XLEN_P-1:0]   div_remainder_signed;

  function automatic logic [XLEN_P-1:0] word_extend(
    input logic [XLEN_P-1:0] value,
    input logic              word_op
  );
    if (word_op)
      word_extend = {{(XLEN_P-32){value[31]}}, value[31:0]};
    else
      word_extend = value;
  endfunction

  always_comb begin
    mul_signed_a = (op_i != MULDIV_MULHU);
    mul_signed_b = (op_i == MULDIV_MUL) || (op_i == MULDIV_MULH);
    div_signed   = !op_i[0];
    operand_a_normalized = operand_a_i;
    operand_b_normalized = operand_b_i;
    if (word_op_i) begin
      if (op_i[2] ? div_signed : mul_signed_a)
        operand_a_normalized = {{(XLEN_P-32){operand_a_i[31]}}, operand_a_i[31:0]};
      else
        operand_a_normalized = {{(XLEN_P-32){1'b0}}, operand_a_i[31:0]};
      if (op_i[2] ? div_signed : mul_signed_b)
        operand_b_normalized = {{(XLEN_P-32){operand_b_i[31]}}, operand_b_i[31:0]};
      else
        operand_b_normalized = {{(XLEN_P-32){1'b0}}, operand_b_i[31:0]};
    end
  end

  assign start_abs_a = ((op_i[2] ? div_signed : mul_signed_a) && operand_a_normalized[XLEN_P-1]) ?
                       (~operand_a_normalized + XLEN_P'(1)) : operand_a_normalized;
  assign start_abs_b = ((op_i[2] ? div_signed : mul_signed_b) && operand_b_normalized[XLEN_P-1]) ?
                       (~operand_b_normalized + XLEN_P'(1)) : operand_b_normalized;
  assign mul_partial = mul_multiplicand_q * mul_multiplier_q[MUL_ITER_BITS-1:0];
  assign mul_acc_next = mul_acc_q + mul_partial;
  assign mul_product_next = mul_negative_q ? (~mul_acc_next + (2*XLEN_P)'(1)) : mul_acc_next;
  assign div_shifted_rem = {div_rem_q[XLEN_P-1:0], div_dividend_q[XLEN_P-1]};
  assign div_ge = div_shifted_rem >= {1'b0, div_divisor_q};
  assign div_rem_next = div_ge ? (div_shifted_rem - {1'b0, div_divisor_q}) : div_shifted_rem;
  assign div_dividend_next = {div_dividend_q[XLEN_P-2:0], 1'b0};
  assign div_quotient_next = {div_quotient_q[XLEN_P-2:0], div_ge};
  assign div_quotient_signed = div_negative_quotient_q ?
                               (~div_quotient_next + XLEN_P'(1)) : div_quotient_next;
  assign div_remainder_signed = div_negative_remainder_q ?
                               (~div_rem_next[XLEN_P-1:0] + XLEN_P'(1)) :
                               div_rem_next[XLEN_P-1:0];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= S_IDLE;
      op_q <= MULDIV_MUL;
      count_q <= '0;
      word_op_q <= 1'b0;
      busy_o <= 1'b0;
      done_o <= 1'b0;
      result_o <= '0;
      mul_acc_q <= '0;
      mul_multiplicand_q <= '0;
      mul_multiplier_q <= '0;
      mul_negative_q <= 1'b0;
      mul_result_pending_q <= '0;
      div_rem_q <= '0;
      div_dividend_q <= '0;
      div_divisor_q <= '0;
      div_quotient_q <= '0;
      div_negative_quotient_q <= 1'b0;
      div_negative_remainder_q <= 1'b0;
      div_return_remainder_q <= 1'b0;
    end else begin
      done_o <= 1'b0;
      if (!busy_o) begin
        if (start_i) begin
          busy_o <= 1'b1;
          op_q <= op_i;
          word_op_q <= word_op_i;
          count_q <= '0;
          if (op_i[2]) begin
            div_return_remainder_q <= op_i[1];
            div_negative_quotient_q <= div_signed &&
                                      (operand_a_normalized[XLEN_P-1] ^ operand_b_normalized[XLEN_P-1]);
            div_negative_remainder_q <= div_signed && operand_a_normalized[XLEN_P-1];
            if (operand_b_normalized == '0) begin
              result_o <= word_extend(op_i[1] ? operand_a_normalized : '1, word_op_i);
              state_q <= S_SPECIAL;
            end else if (div_signed &&
                         (operand_a_normalized == {1'b1, {(XLEN_P-1){1'b0}}}) &&
                         (operand_b_normalized == '1)) begin
              result_o <= word_extend(op_i[1] ? '0 : operand_a_normalized, word_op_i);
              state_q <= S_SPECIAL;
            end else if (start_abs_a < start_abs_b) begin
              result_o <= word_extend(op_i[1] ? operand_a_normalized : '0, word_op_i);
              state_q <= S_SPECIAL;
            end else if (start_abs_a == start_abs_b) begin
              result_o <= word_extend(op_i[1] ? '0 :
                          ((div_signed && (operand_a_normalized[XLEN_P-1] ^ operand_b_normalized[XLEN_P-1])) ?
                           '1 : XLEN_P'(1)), word_op_i);
              state_q <= S_SPECIAL;
            end else begin
              div_rem_q <= '0;
              div_dividend_q <= start_abs_a;
              div_divisor_q <= start_abs_b;
              div_quotient_q <= '0;
              state_q <= S_DIV;
            end
          end else begin
            mul_acc_q <= '0;
            mul_multiplicand_q <= {{XLEN_P{1'b0}}, start_abs_a};
            mul_multiplier_q <= start_abs_b;
            mul_negative_q <= (mul_signed_a && operand_a_normalized[XLEN_P-1]) ^
                              (mul_signed_b && operand_b_normalized[XLEN_P-1]);
            state_q <= S_MUL;
          end
        end
      end else begin
        unique case (state_q)
          S_MUL: begin
            mul_acc_q <= mul_acc_next;
            mul_multiplicand_q <= mul_multiplicand_q << MUL_ITER_BITS;
            mul_multiplier_q <= mul_multiplier_q >> MUL_ITER_BITS;
            if (count_q == MUL_ITER_LAST) begin
              if (MUL_RESULT_REGISTER) begin
                mul_result_pending_q <= (op_q == MULDIV_MUL) ? mul_product_next[XLEN_P-1:0] :
                                                              mul_product_next[2*XLEN_P-1:XLEN_P];
                state_q <= S_MUL_RESULT;
              end else begin
                result_o <= word_extend((op_q == MULDIV_MUL) ? mul_product_next[XLEN_P-1:0] :
                                                                  mul_product_next[2*XLEN_P-1:XLEN_P], word_op_q);
                busy_o <= 1'b0;
                done_o <= 1'b1;
                state_q <= S_IDLE;
              end
            end else begin
              count_q <= count_q + COUNT_W'(1);
            end
          end
          S_MUL_RESULT: begin
            result_o <= word_extend(mul_result_pending_q, word_op_q);
            busy_o <= 1'b0;
            done_o <= 1'b1;
            state_q <= S_IDLE;
          end
          S_DIV: begin
            div_rem_q <= div_rem_next;
            div_dividend_q <= div_dividend_next;
            div_quotient_q <= div_quotient_next;
            if (count_q == COUNT_W'(XLEN_P - 1)) begin
              result_o <= word_extend(div_return_remainder_q ? div_remainder_signed :
                                                               div_quotient_signed, word_op_q);
              busy_o <= 1'b0;
              done_o <= 1'b1;
              state_q <= S_IDLE;
            end else begin
              count_q <= count_q + COUNT_W'(1);
            end
          end
          S_SPECIAL: begin
            busy_o <= 1'b0;
            done_o <= 1'b1;
            state_q <= S_IDLE;
          end
          default: begin
            busy_o <= 1'b0;
            done_o <= 1'b1;
            state_q <= S_IDLE;
          end
        endcase
      end
    end
  end

endmodule
