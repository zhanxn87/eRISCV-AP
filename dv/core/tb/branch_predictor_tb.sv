// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Focused M2 branch-predictor test.
// Verifies cold BTFNT policy, BHT training, and direct-JAL independence.
module branch_predictor_tb;
  logic        clk;
  logic        rst_n;
  logic        bht_update_valid;
  logic [31:0] bht_update_pc;
  logic        bht_update_taken;
  logic        ras_push_valid;
  logic [31:0] ras_push_addr;
  logic        ras_pop_valid;
  logic        enable;
  logic        valid;
  logic        illegal;
  logic [31:0] pc;
  logic [31:0] instr;
  logic        redirect;
  logic [31:0] redirect_pc;
  logic        direct_jump;
  logic        return_pred_valid;
  logic [31:0] return_pred_target;
  logic        branch_pred_valid;
  logic        branch_pred_taken;
  logic        branch_pred_bht_used;
  logic        bht_off_redirect;
  logic [31:0] bht_off_redirect_pc;
  logic        bht_off_direct_jump;
  logic        bht_off_return_pred_valid;
  logic [31:0] bht_off_return_pred_target;
  logic        bht_off_branch_pred_valid;
  logic        bht_off_branch_pred_taken;
  logic        bht_off_branch_pred_bht_used;
  logic        ras_off_redirect;
  logic [31:0] ras_off_redirect_pc;
  logic        ras_off_direct_jump;
  logic        ras_off_return_pred_valid;
  logic [31:0] ras_off_return_pred_target;
  logic        ras_off_branch_pred_valid;
  logic        ras_off_branch_pred_taken;
  logic        ras_off_branch_pred_bht_used;

  branch_predictor dut (
    .clk                   (clk),
    .rst_n                 (rst_n),
    .bht_update_valid_i    (bht_update_valid),
    .bht_update_pc_i       (bht_update_pc),
    .bht_update_taken_i    (bht_update_taken),
    .ras_push_valid_i      (ras_push_valid),
    .ras_push_addr_i       (ras_push_addr),
    .ras_pop_valid_i       (ras_pop_valid),
    .enable_i              (enable),
    .valid_i               (valid),
    .illegal_i             (illegal),
    .pc_i                  (pc),
    .instr_i               (instr),
    .compressed_i          (1'b0),
    .c_instr_i             (16'h0000),
    .redirect_o            (redirect),
    .redirect_pc_o         (redirect_pc),
    .direct_jump_o         (direct_jump),
    .return_pred_valid_o   (return_pred_valid),
    .return_pred_target_o  (return_pred_target),
    .branch_pred_valid_o   (branch_pred_valid),
    .branch_pred_taken_o   (branch_pred_taken),
    .branch_pred_bht_used_o(branch_pred_bht_used)
  );

  // The generated-off configuration must retain BTFNT and omit trained BHT
  // predictions while preserving the same external prediction interface.
  branch_predictor #(
    .ENABLE_BHT_P(1'b0)
  ) bht_off_dut (
    .clk                   (clk),
    .rst_n                 (rst_n),
    .bht_update_valid_i    (bht_update_valid),
    .bht_update_pc_i       (bht_update_pc),
    .bht_update_taken_i    (bht_update_taken),
    .ras_push_valid_i      (ras_push_valid),
    .ras_push_addr_i       (ras_push_addr),
    .ras_pop_valid_i       (ras_pop_valid),
    .enable_i              (enable),
    .valid_i               (valid),
    .illegal_i             (illegal),
    .pc_i                  (pc),
    .instr_i               (instr),
    .compressed_i          (1'b0),
    .c_instr_i             (16'h0000),
    .redirect_o            (bht_off_redirect),
    .redirect_pc_o         (bht_off_redirect_pc),
    .direct_jump_o         (bht_off_direct_jump),
    .return_pred_valid_o   (bht_off_return_pred_valid),
    .return_pred_target_o  (bht_off_return_pred_target),
    .branch_pred_valid_o   (bht_off_branch_pred_valid),
    .branch_pred_taken_o   (bht_off_branch_pred_taken),
    .branch_pred_bht_used_o(bht_off_branch_pred_bht_used)
  );

  // The generated-off configuration must omit all return prediction while
  // preserving direct-jump and conditional-branch prediction.
  branch_predictor #(
    .ENABLE_RAS_P(1'b0)
  ) ras_off_dut (
    .clk                   (clk),
    .rst_n                 (rst_n),
    .bht_update_valid_i    (bht_update_valid),
    .bht_update_pc_i       (bht_update_pc),
    .bht_update_taken_i    (bht_update_taken),
    .ras_push_valid_i      (ras_push_valid),
    .ras_push_addr_i       (ras_push_addr),
    .ras_pop_valid_i       (ras_pop_valid),
    .enable_i              (enable),
    .valid_i               (valid),
    .illegal_i             (illegal),
    .pc_i                  (pc),
    .instr_i               (instr),
    .compressed_i          (1'b0),
    .c_instr_i             (16'h0000),
    .redirect_o            (ras_off_redirect),
    .redirect_pc_o         (ras_off_redirect_pc),
    .direct_jump_o         (ras_off_direct_jump),
    .return_pred_valid_o   (ras_off_return_pred_valid),
    .return_pred_target_o  (ras_off_return_pred_target),
    .branch_pred_valid_o   (ras_off_branch_pred_valid),
    .branch_pred_taken_o   (ras_off_branch_pred_taken),
    .branch_pred_bht_used_o(ras_off_branch_pred_bht_used)
  );

  always #5 clk = ~clk;

  task automatic check(input logic condition, input string message);
    begin
      if (!condition)
        $fatal(1, "branch_predictor_tb: %s", message);
    end
  endtask

  task automatic train(input logic [31:0] train_pc, input logic train_taken);
    begin
      bht_update_pc = train_pc;
      bht_update_taken = train_taken;
      bht_update_valid = 1'b1;
      @(posedge clk);
      #1;
      bht_update_valid = 1'b0;
      // The EX training packet is registered before updating the BHT arrays.
      @(posedge clk);
      #1;
    end
  endtask

  task automatic ras_push(input logic [31:0] return_addr);
    begin
      ras_push_addr = return_addr;
      ras_push_valid = 1'b1;
      @(posedge clk);
      #1;
      ras_push_valid = 1'b0;
    end
  endtask

  task automatic ras_pop;
    begin
      ras_pop_valid = 1'b1;
      @(posedge clk);
      #1;
      ras_pop_valid = 1'b0;
    end
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    bht_update_valid = 1'b0;
    bht_update_pc = '0;
    bht_update_taken = 1'b0;
    ras_push_valid = 1'b0;
    ras_push_addr = '0;
    ras_pop_valid = 1'b0;
    enable = 1'b1;
    valid = 1'b1;
    illegal = 1'b0;
    pc = 32'h0000_0200;
    instr = 32'h0000_0463; // beq x0, x0, +8

    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    #1;

    // Invalid entries retain the existing static forward-not-taken policy.
    check(branch_pred_valid, "forward branch was not classified");
    check(!branch_pred_bht_used, "reset BHT entry must be invalid");
    check(!branch_pred_taken && !redirect, "cold forward branch must not redirect");

    // A taken forward branch seeds weak-taken and changes future direction.
    train(pc, 1'b1);
    #1;
    check(branch_pred_bht_used, "trained entry was not selected");
    check(branch_pred_taken && redirect, "weak-taken entry did not redirect");
    check(!bht_off_branch_pred_bht_used,
          "BHT-off configuration reported a trained entry");
    check(!bht_off_branch_pred_taken && !bht_off_redirect,
          "BHT-off configuration did not retain forward BTFNT");

    // One not-taken result crosses weak-taken to weak-not-taken.
    train(pc, 1'b0);
    #1;
    check(branch_pred_bht_used, "trained entry became invalid");
    check(!branch_pred_taken && !redirect, "counter did not cross to not-taken");

    // These sites share the old PC[6:1] index but differ after folding in
    // PC[12:7]. Opposite outcomes must not destructively retrain one entry.
    pc = 32'h1000_04bc;
    instr = 32'h0000_0463; // beq x0, x0, +8
    train(pc, 1'b1);
    check(branch_pred_bht_used && branch_pred_taken,
          "folded-index first branch was not trained taken");
    train(32'h1000_06bc, 1'b0);
    pc = 32'h1000_04bc;
    #1;
    check(branch_pred_bht_used && branch_pred_taken,
          "folded index aliased opposite-outcome branch sites");

    // A different, still-cold backward branch remains BTFNT taken.
    pc = 32'h0000_0240;
    instr = 32'hfe00_0ee3; // bne x0, x0, -4
    #1;
    check(!branch_pred_bht_used, "untrained backward entry unexpectedly valid");
    check(branch_pred_taken && redirect, "cold backward branch must redirect");
    check(!bht_off_branch_pred_bht_used,
          "BHT-off configuration reported a backward trained entry");
    check(bht_off_branch_pred_taken && bht_off_redirect,
          "BHT-off configuration did not retain backward BTFNT");

    // JAL classification stays independent of BHT state.
    instr = 32'h0080_006f; // jal x0, +8
    #1;
    check(direct_jump && redirect, "direct JAL must redirect independently");
    check(!branch_pred_valid && !branch_pred_bht_used, "JAL must not use BHT");

    // A canonical ABI return has no prediction until a resolved call pushes a
    // return address.  Nested calls use the top entry, then EX-driven pops
    // reveal the older entry. This test covers all four architectural entries
    // and the defined full-stack policy (ignore a fifth push).
    instr = 32'h0000_8067; // jalr x0, 0(x1)
    #1;
    check(!return_pred_valid && !redirect, "empty RAS must not predict return");

    ras_push(32'h0000_0304);
    #1;
    check(return_pred_valid && redirect, "RAS did not predict a return");
    check(return_pred_target == 32'h0000_0304 && redirect_pc == 32'h0000_0304,
          "RAS returned incorrect first address");
    // Eligibility qualifies redirect_o only. The address data remains the
    // registered RAS top while disabled, so an older redirect/stall control
    // signal cannot become part of the return-target mux cone.
    enable = 1'b0;
    #1;
    check(!return_pred_valid && !redirect, "disabled RAS prediction redirected");
    check(redirect_pc == 32'h0000_0304,
          "disabled RAS prediction changed its ignored target data");
    enable = 1'b1;
    #1;
    check(!ras_off_return_pred_valid && !ras_off_redirect,
          "RAS-off configuration predicted a return");
    check(ras_off_return_pred_target == 32'h0000_0000,
          "RAS-off configuration exposed a return target");

    ras_push(32'h0000_0408);
    #1;
    check(return_pred_target == 32'h0000_0408, "RAS did not use nested top");

    ras_push(32'h0000_050c);
    ras_push(32'h0000_0610);
    #1;
    check(return_pred_target == 32'h0000_0610, "RAS did not retain fourth entry");

    ras_push(32'h0000_0714);
    #1;
    check(return_pred_target == 32'h0000_0610, "full RAS must ignore fifth push");

    ras_pop();
    #1;
    check(return_pred_target == 32'h0000_050c, "RAS pop did not restore third entry");

    ras_pop();
    #1;
    check(return_pred_target == 32'h0000_0408, "RAS pop did not restore second entry");

    ras_pop();
    #1;
    check(return_pred_target == 32'h0000_0304, "RAS pop did not restore first entry");

    ras_pop();
    #1;
    check(!return_pred_valid && !redirect, "RAS empty pop contract failed");

    $display("BRANCH_PREDICTOR_TB PASS");
    $finish;
  end
endmodule
