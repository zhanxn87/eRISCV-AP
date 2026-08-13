// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// Focused single-port local-TCM arbitration test.
module tcm_arbitration_tb;

  logic clk, rst_n;
  logic imem_rd_req, imem_ready, imem_rvalid;
  logic [3:0] imem_addr;
  logic [31:0] imem_rdata;
  logic imem_boot_we;
  logic [3:0] imem_boot_addr;
  logic [31:0] imem_boot_wdata;
  logic [3:0] imem_boot_be;
  logic imem_data_req, imem_data_we, imem_data_resp_valid, imem_data_err;
  logic [3:0] imem_data_be, imem_data_addr;
  logic [31:0] imem_data_wdata, imem_data_rdata;

  logic sba_req, sba_dmem_req, sba_we, mem_req, mem_we;
  logic [3:0] sba_be, mem_be;
  logic [31:0] sba_addr, sba_wdata, mem_addr, mem_wdata;
  logic dmem_req, dmem_we, dmem_resp_valid, dmem_resp_write, dmem_err;
  logic [3:0] dmem_be, dmem_addr;
  logic [31:0] dmem_addr_bus, dmem_wdata, dmem_rdata;
  logic mem_write_accept, mem_resp_valid, mem_err, sba_resp_valid, sba_err;
  logic [31:0] mem_rdata, sba_rdata;
  logic lmem_req, lmem_accept, lmem_resp_valid, lmem_err;
  logic [31:0] lmem_addr, lmem_rdata;
  int errors;

  instr_mem #(.ADDR_WIDTH(4), .READ_LATENCY(1)) imem_i (
    .clk, .rst_n, .rd_req_i(imem_rd_req), .ready_o(imem_ready),
    .addr_i(imem_addr), .rvalid_o(imem_rvalid), .instr_o(imem_rdata),
    .boot_we_i(imem_boot_we), .boot_addr_i(imem_boot_addr),
    .boot_wdata_i(imem_boot_wdata), .boot_be_i(imem_boot_be),
    .data_req_i(imem_data_req), .data_we_i(imem_data_we),
    .data_be_i(imem_data_be), .data_addr_i(imem_data_addr),
    .data_wdata_i(imem_data_wdata), .data_resp_valid_o(imem_data_resp_valid),
    .data_rdata_o(imem_data_rdata), .data_err_o(imem_data_err)
  );

  data_mem_arbiter dmem_arbiter_i (
    .clk, .rst_n, .sba_req_i(sba_req), .sba_dmem_req_i(sba_dmem_req),
    .sba_we_i(sba_we), .sba_be_i(sba_be), .sba_addr_i(sba_addr),
    .sba_wdata_i(sba_wdata), .sba_resp_valid_o(sba_resp_valid),
    .sba_rdata_o(sba_rdata), .sba_err_o(sba_err),
    .mem_req_i(mem_req), .mem_we_i(mem_we),
    .mem_be_i(mem_be), .mem_addr_i(mem_addr), .mem_wdata_i(mem_wdata),
    .mem_write_accept_o(mem_write_accept), .mem_resp_valid_o(mem_resp_valid),
    .mem_rdata_o(mem_rdata), .mem_err_o(mem_err),
    .lmem_req_i(lmem_req), .lmem_addr_i(lmem_addr), .lmem_accept_o(lmem_accept),
    .lmem_resp_valid_o(lmem_resp_valid), .lmem_rdata_o(lmem_rdata),
    .lmem_err_o(lmem_err),
    .dmem_req_o(dmem_req), .dmem_we_o(dmem_we), .dmem_be_o(dmem_be),
    .dmem_addr_o(dmem_addr_bus), .dmem_wdata_o(dmem_wdata),
    .dmem_resp_valid_i(dmem_resp_valid), .dmem_resp_write_i(dmem_resp_write),
    .dmem_rdata_i(dmem_rdata), .dmem_err_i(dmem_err)
  );

  data_mem #(.ADDR_WIDTH(4), .READ_LATENCY(1)) dmem_i (
    .clk, .rst_n, .req_i(dmem_req), .we_i(dmem_we), .be_i(dmem_be),
    .addr_i(dmem_addr), .wdata_i(dmem_wdata), .resp_valid_o(dmem_resp_valid),
    .resp_write_o(dmem_resp_write),
    .rdata_o(dmem_rdata), .err_o(dmem_err)
  );

  assign dmem_addr = dmem_addr_bus[5:2];

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic check(input logic condition, input string message);
    if (!condition) begin
      errors = errors + 1;
      $display("TCM ARBITRATION FAIL: %s", message);
    end
  endtask

  initial begin
    rst_n = 1'b0;
    imem_rd_req = 1'b0; imem_addr = '0;
    imem_boot_we = 1'b0; imem_boot_addr = '0; imem_boot_wdata = '0; imem_boot_be = '0;
    imem_data_req = 1'b0; imem_data_we = 1'b0; imem_data_be = '0;
    imem_data_addr = '0; imem_data_wdata = '0;
    sba_req = 1'b0; sba_dmem_req = 1'b0; sba_we = 1'b0; sba_be = '0;
    sba_addr = '0; sba_wdata = '0; mem_req = 1'b0; mem_we = 1'b0; mem_be = '0;
    mem_addr = '0; mem_wdata = '0; lmem_req = 1'b0; lmem_addr = '0; errors = 0;
    imem_i.sram_i.mem[1] = 32'h1111_1111;
    imem_i.sram_i.mem[2] = 32'h2222_2222;

    repeat (2) @(posedge clk);
    rst_n = 1'b1;

    // One cycle with all IMEM clients active proves boot > DBus > IF.
    @(negedge clk);
    imem_boot_we = 1'b1; imem_boot_addr = 4'd3; imem_boot_wdata = 32'hb007_0001; imem_boot_be = 4'hf;
    imem_data_req = 1'b1; imem_data_addr = 4'd2; imem_data_be = 4'hf;
    imem_rd_req = 1'b1; imem_addr = 4'd1;
    #1 check(!imem_ready, "boot write must block DBus/IF admission");
    @(posedge clk); #1;
    check(imem_i.sram_i.mem[3] == 32'hb007_0001, "boot write was not selected");
    check(!imem_data_resp_valid && !imem_rvalid, "boot write must not create a read response");

    @(negedge clk);
    imem_boot_we = 1'b0;
    #1 check(!imem_ready, "DBus must block IF admission after boot write");
    @(posedge clk); #1;
    check(imem_data_resp_valid && !imem_rvalid, "DBus response must follow the accepted DBus request");
    check(imem_data_rdata == 32'h2222_2222, "DBus read data mismatch");

    @(negedge clk);
    imem_data_req = 1'b0;
    #1 check(imem_ready, "IF must be admitted when boot and DBus are idle");
    @(posedge clk); #1;
    check(imem_rvalid && !imem_data_resp_valid, "IF response must follow the accepted IF request");
    check(imem_rdata == 32'h1111_1111, "IF read data mismatch");
    imem_rd_req = 1'b0;

    // A same-cycle Debug SBA/CPU DMEM collision must complete SBA first.
    @(negedge clk);
    sba_req = 1'b1; sba_dmem_req = 1'b1; sba_we = 1'b1; sba_be = 4'hf;
    sba_addr = 32'h0000_0008; sba_wdata = 32'h5ba0_0001;
    mem_req = 1'b1; mem_we = 1'b1; mem_be = 4'hf;
    mem_addr = 32'h0000_0004; mem_wdata = 32'hc0de_0001;
    #1 check(dmem_req && dmem_we && dmem_addr_bus == 32'h0000_0008 && dmem_wdata == 32'h5ba0_0001,
             "SBA must own a same-cycle DMEM collision");
    @(posedge clk); #1;
    check(sba_resp_valid && !mem_resp_valid,
          "SBA response must not be delivered to the CPU");
    check(dmem_i.sram_i.mem[2] == 32'h5ba0_0001, "SBA write data mismatch");

    @(negedge clk);
    sba_req = 1'b0; sba_dmem_req = 1'b0;
    #1 check(dmem_req && dmem_we && dmem_addr_bus == 32'h0000_0004 && dmem_wdata == 32'hc0de_0001,
             "CPU request must be admitted after one SBA transaction");
    @(posedge clk); #1;
    check(mem_write_accept && !mem_resp_valid && !sba_resp_valid,
          "CPU DTCM write must complete through the fast-accept path");
    check(dmem_i.sram_i.mem[1] == 32'hc0de_0001, "CPU write data mismatch");
    mem_req = 1'b0;

    // An idle EX-stage local read owns the port and receives its response.
    @(negedge clk);
    lmem_req = 1'b1; lmem_addr = 32'h0000_0004;
    #1 check(lmem_accept && dmem_req && !dmem_we &&
             dmem_addr_bus == 32'h0000_0004,
             "idle local-load candidate must claim the DTCM port");
    @(posedge clk); #1;
    check(lmem_resp_valid && !mem_resp_valid && !sba_resp_valid &&
          lmem_rdata == 32'hc0de_0001,
          "local-load response must be returned only to its owner");
    lmem_req = 1'b0;

    // A normal MEM request retains priority, forcing the local-load path to
    // fall back to the address-agnostic D-bus transaction.
    @(negedge clk);
    lmem_req = 1'b1; lmem_addr = 32'h0000_0004;
    mem_req = 1'b1; mem_we = 1'b0; mem_addr = 32'h0000_0004;
    #1 check(!lmem_accept && dmem_req && !dmem_we &&
             dmem_addr_bus == 32'h0000_0004,
             "normal MEM request must block a same-cycle local-load candidate");
    @(posedge clk); #1;
    check(mem_resp_valid && !lmem_resp_valid,
          "normal MEM response must not be delivered to local-load");
    mem_req = 1'b0; lmem_req = 1'b0;

    if (errors == 0)
      $display("TCM ARBITRATION PASS: IMEM boot>DBus>IF and DMEM SBA>CPU>LMEM");
    else
      $display("TCM ARBITRATION FAIL: errors=%0d", errors);
    $finish;
  end

endmodule
