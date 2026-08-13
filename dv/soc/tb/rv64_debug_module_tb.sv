// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

module rv64_debug_module_tb;
  localparam logic [6:0] DMI_DATA0 = 7'h04;
  localparam logic [6:0] DMI_DATA1 = 7'h05;
  localparam logic [6:0] DMI_DMCONTROL = 7'h10;
  localparam logic [6:0] DMI_ABSTRACTCS = 7'h16;
  localparam logic [6:0] DMI_COMMAND = 7'h17;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic dmi_req_valid;
  logic [6:0] dmi_req_addr;
  logic [31:0] dmi_req_wdata;
  logic [1:0] dmi_req_op;
  logic dmi_resp_valid;
  logic [31:0] dmi_resp_rdata;
  logic [1:0] dmi_resp_op;
  logic hart_halt_req, hart_resume_req;
  logic debug_reg_req_valid, debug_reg_write, debug_reg_error;
  logic [15:0] debug_reg_addr;
  logic [63:0] debug_reg_wdata, debug_reg_rdata;

  debug_module_min dut (
    .clk, .rst_n,
    .dmi_req_valid_i(dmi_req_valid), .dmi_req_addr_i(dmi_req_addr),
    .dmi_req_wdata_i(dmi_req_wdata), .dmi_req_op_i(dmi_req_op),
    .dmi_resp_valid_o(dmi_resp_valid), .dmi_resp_rdata_o(dmi_resp_rdata),
    .dmi_resp_op_o(dmi_resp_op),
    .hart_halt_req_o(hart_halt_req), .hart_resume_req_o(hart_resume_req),
    .hart_halted_i(1'b1), .hart_running_i(1'b0), .hart_pc_i(64'h1_0000_0100),
    .hart_cause_i(3'd3), .debug_reg_req_valid_o(debug_reg_req_valid),
    .debug_reg_write_o(debug_reg_write), .debug_reg_addr_o(debug_reg_addr),
    .debug_reg_wdata_o(debug_reg_wdata), .debug_reg_rdata_i(debug_reg_rdata),
    .debug_reg_error_i(debug_reg_error)
  );

  task automatic dmi_write(input logic [6:0] addr, input logic [31:0] value);
    begin
      @(negedge clk);
      dmi_req_valid = 1'b1;
      dmi_req_addr = addr;
      dmi_req_wdata = value;
      dmi_req_op = 2'b10;
      @(negedge clk);
      dmi_req_valid = 1'b0;
      dmi_req_op = 2'b00;
    end
  endtask

  task automatic dmi_read(input logic [6:0] addr, output logic [31:0] value);
    begin
      @(negedge clk);
      dmi_req_valid = 1'b1;
      dmi_req_addr = addr;
      dmi_req_op = 2'b01;
      #1 value = dmi_resp_rdata;
      @(negedge clk);
      dmi_req_valid = 1'b0;
      dmi_req_op = 2'b00;
    end
  endtask

  initial begin
    logic [31:0] data0;
    logic [31:0] data1;
    logic [31:0] abstractcs;
    dmi_req_valid = 1'b0;
    dmi_req_addr = '0;
    dmi_req_wdata = '0;
    dmi_req_op = 2'b00;
    debug_reg_rdata = 64'hfedc_ba98_7654_3210;
    debug_reg_error = 1'b0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    dmi_write(DMI_DMCONTROL, 32'h0000_0001);
    dmi_write(DMI_DATA0, 32'h89ab_cdef);
    dmi_write(DMI_DATA1, 32'h0123_4567);

    @(negedge clk);
    dmi_req_valid = 1'b1;
    dmi_req_addr = DMI_COMMAND;
    dmi_req_wdata = 32'h0033_1006;
    dmi_req_op = 2'b10;
    #1;
    if (!debug_reg_req_valid || !debug_reg_write || (debug_reg_addr != 16'h1006) ||
        (debug_reg_wdata != 64'h0123_4567_89ab_cdef))
      $fatal(1, "RV64 abstract write did not present data0/data1 as one XLEN value");
    @(negedge clk);
    dmi_req_valid = 1'b0;
    dmi_req_op = 2'b00;

    dmi_write(DMI_COMMAND, 32'h0032_1005);
    dmi_read(DMI_DATA0, data0);
    dmi_read(DMI_DATA1, data1);
    if ({data1, data0} != 64'hfedc_ba98_7654_3210)
      $fatal(1, "RV64 abstract read lost upper data1 word: %h_%h", data1, data0);

    dmi_write(DMI_COMMAND, 32'h0022_1005);
    dmi_read(DMI_ABSTRACTCS, abstractcs);
    if (abstractcs[10:8] != 3'd2)
      $fatal(1, "RV32 aarsize must be rejected on RV64, cmderr=%0d", abstractcs[10:8]);

    $display("RV64_DEBUG_MODULE PASS");
    $finish;
  end
endmodule
