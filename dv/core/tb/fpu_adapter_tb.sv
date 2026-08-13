// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

module fpu_adapter_tb;
  import riscv_pkg::*;

  logic         clk;
  logic         rst_n;
  logic         issue_valid;
  logic         issue_ready;
  logic         flush;
  fp_issue_t    issue;
  logic         complete_valid;
  fp_complete_t complete;
  logic         busy;

  always #5 clk = ~clk;

  fpu_adapter dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .issue_valid_i    (issue_valid),
    .issue_i          (issue),
    .issue_ready_o    (issue_ready),
    .flush_i          (flush),
    .complete_valid_o (complete_valid),
    .complete_o       (complete),
    .complete_ready_i (1'b1),
    .busy_o           (busy)
  );

  task automatic execute_and_check(
    input fp_operation_e operation,
    input logic          operation_modifier,
    input logic [31:0]   operand_a,
    input logic [31:0]   operand_b,
    input logic [31:0]   operand_c,
    input logic [31:0]   expected_result,
    input logic [4:0]    expected_fflags
  );
    bit completion_seen;
    int timeout_cycles;
    logic [31:0] completion_result;
    logic [4:0]  completion_fflags;
    @(negedge clk);
    issue = '0;
    issue.operand_a          = {32'hffff_ffff, operand_a};
    issue.operand_b          = {32'hffff_ffff, operand_b};
    issue.operand_c          = {32'hffff_ffff, operand_c};
    issue.operation          = operation;
    issue.operation_modifier = operation_modifier;
    issue.rounding_mode      = 3'b000;
    issue_valid              = 1'b1;

    do @(posedge clk); while (!issue_ready);
    @(negedge clk);
    issue_valid = 1'b0;

    completion_seen = 1'b0;
    completion_result = '0;
    completion_fflags = '0;
    for (timeout_cycles = 0; timeout_cycles < 80; timeout_cycles++) begin
      @(posedge clk);
      if (complete_valid) begin
        completion_seen = 1'b1;
        completion_result = complete.result;
        completion_fflags = complete.fflags;
        break;
      end
    end
    if (!completion_seen) begin
      $fatal(1, "FPU completion timeout for op=%0d", operation);
    end
    if (completion_result !== expected_result) begin
      $fatal(1, "FPU result got %08h, expected %08h", completion_result, expected_result);
    end
    if (completion_fflags !== expected_fflags) begin
      $fatal(1, "FPU flags got %02h, expected %02h", completion_fflags,
             expected_fflags);
    end
  endtask

  task automatic execute_and_check_d(
    input fp_operation_e operation,
    input logic          operation_modifier,
    input logic [63:0]   operand_a,
    input logic [63:0]   operand_b,
    input logic [63:0]   operand_c,
    input logic [63:0]   expected_result,
    input logic [4:0]    expected_fflags
  );
    bit completion_seen;
    int timeout_cycles;
    logic [63:0] completion_result;
    logic [4:0]  completion_fflags;
    @(negedge clk);
    issue = '0;
    issue.operand_a          = operand_a;
    issue.operand_b          = operand_b;
    issue.operand_c          = operand_c;
    issue.operation          = operation;
    issue.operation_modifier = operation_modifier;
    issue.rounding_mode      = 3'b000;
    issue.src_fmt            = FP_FMT_D;
    issue.dst_fmt            = FP_FMT_D;
    issue_valid              = 1'b1;

    do @(posedge clk); while (!issue_ready);
    @(negedge clk);
    issue_valid = 1'b0;

    completion_seen = 1'b0;
    completion_result = '0;
    completion_fflags = '0;
    for (timeout_cycles = 0; timeout_cycles < 160; timeout_cycles++) begin
      @(posedge clk);
      if (complete_valid) begin
        completion_seen = 1'b1;
        completion_result = complete.result;
        completion_fflags = complete.fflags;
        break;
      end
    end
    if (!completion_seen) begin
      $fatal(1, "FP64 completion timeout for op=%0d", operation);
    end
    if (completion_result !== expected_result) begin
      $fatal(1, "FP64 result got %016h, expected %016h", completion_result, expected_result);
    end
    if (completion_fflags !== expected_fflags) begin
      $fatal(1, "FP64 flags got %02h, expected %02h", completion_fflags,
             expected_fflags);
    end
  endtask

  initial begin
    #20000;
    $fatal(1, "FPU adapter test timed out");
  end

  initial begin
    clk         = 1'b0;
    rst_n       = 1'b0;
    issue_valid = 1'b0;
    flush       = 1'b0;
    issue       = '0;

    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // CVFPU ADD/SUB use B +/- C; A is ignored by the arithmetic unit.
    execute_and_check(FP_OP_ADD, 1'b0, 32'h3f80_0000, 32'h3f80_0000,
                      32'h4000_0000, 32'h4040_0000, 5'b0); // 1.0 + 2.0 = 3.0
    execute_and_check(FP_OP_ADD, 1'b1, 32'h3f80_0000, 32'h4040_0000,
                      32'h3f80_0000, 32'h4000_0000, 5'b0); // 3.0 - 1.0 = 2.0
    execute_and_check(FP_OP_SGNJ, 1'b1, 32'h3f80_0000, 32'h3f80_0000,
                      32'h0000_0000, 32'h3f80_0000, 5'b0); // FMV.W.X transfer encoding
    execute_and_check(FP_OP_SGNJ, 1'b1, 32'h4080_0000, 32'h4080_0000,
                      32'h0000_0000, 32'h4080_0000, 5'b0); // FMV.X.W transfer encoding
    execute_and_check(FP_OP_MUL, 1'b0, 32'h3f80_0000, 32'h4000_0000,
                      32'h0000_0000, 32'h4000_0000, 5'b0); // 1.0 * 2.0 = 2.0
    execute_and_check(FP_OP_FMADD, 1'b0, 32'h4000_0000, 32'h4040_0000,
                      32'h4080_0000, 32'h4120_0000, 5'b0); // 2.0 * 3.0 + 4.0 = 10.0
    execute_and_check(FP_OP_FNMSUB, 1'b0, 32'h4000_0000, 32'h4040_0000,
                      32'h4080_0000, 32'hc000_0000, 5'b0); // -(2.0 * 3.0) + 4.0 = -2.0
    execute_and_check(FP_OP_DIV, 1'b0, 32'h4040_0000, 32'h4000_0000,
                      32'h0000_0000, 32'h3fc0_0000, 5'b0); // 3.0 / 2.0 = 1.5
    execute_and_check(FP_OP_DIV, 1'b0, 32'h4040_0000, 32'h4110_0000,
                      32'h0000_0000, 32'h3eaa_aaab, 5'b00001); // 3.0 / 9.0 = 1/3
    execute_and_check(FP_OP_DIV, 1'b0, 32'hbf80_0000, 32'h4040_0000,
                      32'h0000_0000, 32'hbeaa_aaab, 5'b00001); // -1.0 / 3.0 = -1/3
    execute_and_check(FP_OP_CMP, 1'b0, 32'h0000_0000, 32'hbf80_0000,
                      32'h0000_0000, 32'h0000_0000, 5'b0); // 0.0 <= -1.0 is false
    execute_and_check(FP_OP_CMP, 1'b0, 32'hbf80_0000, 32'h0000_0000,
                      32'h0000_0000, 32'h0000_0001, 5'b0); // -1.0 <= 0.0 is true
    execute_and_check(FP_OP_DIV, 1'b0, 32'h4080_0000, 32'h4000_0000,
                      32'h0000_0000, 32'h4000_0000, 5'b0); // 4.0 / 2.0 = 2.0
    execute_and_check(FP_OP_DIV, 1'b0, 32'h40a0_0000, 32'h4000_0000,
                      32'h0000_0000, 32'h4020_0000, 5'b0); // 5.0 / 2.0 = 2.5

    // RV64D operations use the same 64-bit architectural FPR payload end to
    // end. SGNJ with identical sources is the FMV.D.X/X.D transport encoding.
    execute_and_check_d(FP_OP_SGNJ, 1'b1, 64'h3ff0_0000_0000_0000,
                        64'h3ff0_0000_0000_0000, 64'h0,
                        64'h3ff0_0000_0000_0000, 5'b0);
    execute_and_check_d(FP_OP_ADD, 1'b0, 64'h0,
                        64'h3ff0_0000_0000_0000, 64'h4000_0000_0000_0000,
                        64'h4008_0000_0000_0000, 5'b0);

    $display("FPU_ADAPTER_TB PASS");
    $finish;
  end

endmodule
