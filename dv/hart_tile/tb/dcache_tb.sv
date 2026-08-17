// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

module dcache_tb;

  localparam int unsigned PADDR_W = 48;
  localparam int unsigned LINE_BYTES = 64;
  localparam int unsigned LINE_BITS = LINE_BYTES * 8;
  localparam logic [3:0] ATOMIC_NONE = 4'd0;
  localparam logic [3:0] ATOMIC_LR   = 4'd1;
  localparam logic [3:0] ATOMIC_SC   = 4'd2;
  localparam logic [3:0] ATOMIC_ADD  = 4'd4;
  localparam logic [1:0] CBO_INVAL = 2'd1;
  localparam logic [1:0] CBO_CLEAN = 2'd2;
  localparam logic [1:0] CBO_FLUSH = 2'd3;

  logic clk;
  logic rst_n;
  logic cpu_req;
  logic [PADDR_W-1:0] cpu_addr;
  logic [63:0] cpu_wdata;
  logic cpu_we;
  logic [7:0] cpu_be;
  logic [3:0] cpu_atomic_op;
  logic cpu_resp_valid;
  logic [63:0] cpu_rdata;
  logic cpu_err;
  logic flush;
  logic flush_done;
  logic flush_err;
  logic cbo_req;
  logic [PADDR_W-1:0] cbo_addr;
  logic [1:0] cbo_op;
  logic cbo_ready;
  logic cbo_done;
  logic cbo_err;
  logic line_req;
  logic line_we;
  logic [PADDR_W-1:0] line_addr;
  logic [LINE_BITS-1:0] line_wdata;
  logic line_resp_valid;
  logic [LINE_BITS-1:0] line_rdata;
  logic line_err;
  int failures;

  dcache dut (
    .clk(clk), .rst_n(rst_n),
    .cpu_req_i(cpu_req), .cpu_addr_i(cpu_addr), .cpu_wdata_i(cpu_wdata),
    .cpu_we_i(cpu_we), .cpu_be_i(cpu_be), .cpu_atomic_op_i(cpu_atomic_op),
    .cpu_resp_valid_o(cpu_resp_valid), .cpu_rdata_o(cpu_rdata), .cpu_err_o(cpu_err),
    .flush_i(flush), .flush_done_o(flush_done), .flush_err_o(flush_err),
    .cbo_req_i(cbo_req), .cbo_addr_i(cbo_addr), .cbo_op_i(cbo_op),
    .cbo_ready_o(cbo_ready), .cbo_done_o(cbo_done), .cbo_err_o(cbo_err),
    .line_req_o(line_req), .line_we_o(line_we), .line_addr_o(line_addr),
    .line_wdata_o(line_wdata), .line_resp_valid_i(line_resp_valid),
    .line_rdata_i(line_rdata), .line_err_i(line_err)
  );

  dcache_line_mem backing_mem_i (
    .clk(clk), .rst_n(rst_n), .req_i(line_req), .we_i(line_we),
    .addr_i(line_addr), .wdata_i(line_wdata), .resp_valid_o(line_resp_valid),
    .rdata_o(line_rdata), .err_o(line_err)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic check(input logic condition, input string message);
    begin
      if (!condition) begin
        failures = failures + 1;
        $error("DCACHE FAIL: %s", message);
      end
    end
  endtask

  task automatic set_backing_word(
    input logic [PADDR_W-1:0] address,
    input logic [63:0] value
  );
    logic [13:0] line_index;
    logic [2:0] word_index;
    begin
      line_index = address[19:6];
      word_index = address[5:3];
      backing_mem_i.mem[line_index][word_index * 64 +: 64] = value;
    end
  endtask

  task automatic expect_backing_word(
    input logic [PADDR_W-1:0] address,
    input logic [63:0] value,
    input string message
  );
    logic [13:0] line_index;
    logic [2:0] word_index;
    begin
      line_index = address[19:6];
      word_index = address[5:3];
      check(backing_mem_i.mem[line_index][word_index * 64 +: 64] === value, message);
    end
  endtask

  task automatic do_cpu_request(
    input logic [PADDR_W-1:0] address,
    input logic write_enable,
    input logic [7:0] byte_enable,
    input logic [63:0] write_data,
    input logic [3:0] atomic_op,
    output logic [63:0] read_data,
    output logic got_error
  );
    int unsigned timeout_cycles;
    begin
      @(negedge clk);
      cpu_addr = address;
      cpu_we = write_enable;
      cpu_be = byte_enable;
      cpu_wdata = write_data;
      cpu_atomic_op = atomic_op;
      cpu_req = 1'b1;
      @(negedge clk);
      cpu_req = 1'b0;
      cpu_we = 1'b0;
      cpu_be = '0;
      cpu_wdata = '0;
      cpu_atomic_op = ATOMIC_NONE;
      timeout_cycles = 0;
      do begin
        @(posedge clk);
        #1;
        timeout_cycles = timeout_cycles + 1;
        if (timeout_cycles > 100) begin
          $fatal(1, "DCACHE request timeout state=%0d line_req=%0b line_resp=%0b",
                 dut.state_q, line_req, line_resp_valid);
        end
      end while (!cpu_resp_valid);
      read_data = cpu_rdata;
      got_error = cpu_err;
    end
  endtask

  task automatic do_cbo(
    input logic [PADDR_W-1:0] address,
    input logic [1:0] operation
  );
    int unsigned timeout_cycles;
    begin
      @(negedge clk);
      cbo_addr = address;
      cbo_op = operation;
      cbo_req = 1'b1;
      do @(posedge clk); while (!cbo_ready);
      @(negedge clk);
      cbo_req = 1'b0;
      cbo_addr = '0;
      cbo_op = '0;
      timeout_cycles = 0;
      do begin
        @(posedge clk);
        #1;
        timeout_cycles = timeout_cycles + 1;
        if (timeout_cycles > 100)
          $fatal(1, "DCACHE CBO timeout state=%0d", dut.state_q);
      end while (!cbo_done);
      check(!cbo_err, "CBO reported an unexpected backing-memory error");
      @(negedge clk);
    end
  endtask

  task automatic do_flush;
    int unsigned timeout_cycles;
    begin
      @(negedge clk);
      flush = 1'b1;
      @(posedge clk);
      #1;
      flush = 1'b0;
    cbo_req = 1'b0;
    cbo_addr = '0;
    cbo_op = '0;
      timeout_cycles = 0;
      do begin
        @(posedge clk);
        #1;
        timeout_cycles = timeout_cycles + 1;
        if (timeout_cycles > 1000) begin
          $fatal(1, "DCACHE flush timeout state=%0d set=%0d way=%0d",
                 dut.state_q, dut.flush_set_q, dut.flush_way_q);
        end
      end while (!flush_done);
      check(!flush_err, "flush reported an unexpected backing-memory error");
      @(negedge clk);
    end
  endtask

  logic [63:0] observed;
  logic observed_err;
  localparam logic [PADDR_W-1:0] ADDR_A = 48'h0000_0000;
  localparam logic [PADDR_W-1:0] ADDR_B = 48'h0000_4000;
  localparam logic [PADDR_W-1:0] ADDR_C = 48'h0000_8000;
  localparam logic [PADDR_W-1:0] ADDR_ATOMIC = 48'h0000_1200;

  initial begin
    failures = 0;
    rst_n = 1'b0;
    cpu_req = 1'b0;
    cpu_addr = '0;
    cpu_wdata = '0;
    cpu_we = 1'b0;
    cpu_be = '0;
    cpu_atomic_op = ATOMIC_NONE;
    flush = 1'b0;
    cbo_req = 1'b0;
    cbo_addr = '0;
    cbo_op = '0;
    repeat (2) @(posedge clk);

    set_backing_word(ADDR_A, 64'h0102_0304_0506_0708);
    set_backing_word(ADDR_A + 48'd8, 64'h1111_2222_3333_4444);
    set_backing_word(ADDR_B, 64'h2222_3333_4444_5555);
    set_backing_word(ADDR_C, 64'h3333_4444_5555_6666);
    set_backing_word(ADDR_ATOMIC, 64'h0000_0000_0000_0010);
    rst_n = 1'b1;

    do_cpu_request(ADDR_A, 1'b0, 8'hff, '0, ATOMIC_NONE, observed, observed_err);
    check(!observed_err, "initial refill load returned an error");
    check(observed === 64'h0102_0304_0506_0708, "initial refill load returned wrong data");

    do_cpu_request(ADDR_A + 48'd8, 1'b1, 8'hff, 64'haaaa_bbbb_cccc_dddd,
                   ATOMIC_NONE, observed, observed_err);
    check(!observed_err, "store hit returned an error");
    expect_backing_word(ADDR_A + 48'd8, 64'h1111_2222_3333_4444,
                        "write-back store leaked to backing memory before eviction");
    do_cpu_request(ADDR_A + 48'd8, 1'b0, 8'hff, '0, ATOMIC_NONE, observed, observed_err);
    check(observed === 64'haaaa_bbbb_cccc_dddd, "store hit was not observed by a later load");

    // The CPU bus presents narrow stores pre-shifted within their containing
    // 64-bit word, together with pre-shifted byte enables.
    do_cpu_request(ADDR_A + 48'd2, 1'b1, 8'h0c, 64'h0000_0000_ffff_0000,
                   ATOMIC_NONE, observed, observed_err);
    do_cpu_request(ADDR_A, 1'b0, 8'hff, '0, ATOMIC_NONE, observed, observed_err);
    check(observed === 64'h0102_0304_ffff_0708,
          "pre-shifted SH byte lanes were not written at their addressed offsets");

    // A, B and C have identical set indices. The third fill evicts dirty A.
    do_cpu_request(ADDR_B, 1'b0, 8'hff, '0, ATOMIC_NONE, observed, observed_err);
    do_cpu_request(ADDR_C, 1'b0, 8'hff, '0, ATOMIC_NONE, observed, observed_err);
    expect_backing_word(ADDR_A + 48'd8, 64'haaaa_bbbb_cccc_dddd,
                        "dirty victim was not written back before refill");

    do_cpu_request(ADDR_B, 1'b1, 8'hff, 64'hdead_beef_0123_4567,
                   ATOMIC_NONE, observed, observed_err);
    do_flush();
    expect_backing_word(ADDR_B, 64'hdead_beef_0123_4567,
                        "flush did not write back dirty cache line");

    do_cpu_request(ADDR_ATOMIC, 1'b0, 8'hff, '0, ATOMIC_LR, observed, observed_err);
    check(observed === 64'h10, "LR.D returned wrong value");
    do_cpu_request(ADDR_ATOMIC, 1'b0, 8'hff, 64'h20, ATOMIC_SC, observed, observed_err);
    check(observed === 64'h0, "SC.D after LR.D did not succeed");
    do_cpu_request(ADDR_ATOMIC, 1'b0, 8'hff, '0, ATOMIC_NONE, observed, observed_err);
    check(observed === 64'h20, "successful SC.D did not update cached word");

    // SC.W uses a pre-shifted high-word mask at byte offset four. This
    // catches an accidental second application of the byte offset in cache.
    do_cpu_request(ADDR_ATOMIC + 48'd8, 1'b1, 8'hff, 64'h1111_1111_0000_0000,
                   ATOMIC_NONE, observed, observed_err);
    do_cpu_request(ADDR_ATOMIC + 48'd12, 1'b0, 8'hf0, '0, ATOMIC_LR, observed, observed_err);
    check(observed === 64'h1111_1111_0000_0000, "LR.W upper word returned wrong data");
    do_cpu_request(ADDR_ATOMIC + 48'd12, 1'b0, 8'hf0, 64'h2222_2222_0000_0000,
                   ATOMIC_SC, observed, observed_err);
    check(observed === 64'h0, "SC.W upper word after LR.W did not succeed");
    do_cpu_request(ADDR_ATOMIC + 48'd8, 1'b0, 8'hff, '0, ATOMIC_NONE, observed, observed_err);
    check(observed === 64'h2222_2222_0000_0000,
          "SC.W upper word did not update its addressed byte lanes");

    do_cpu_request(ADDR_ATOMIC, 1'b0, 8'hff, '0, ATOMIC_LR, observed, observed_err);
    do_cpu_request(ADDR_ATOMIC, 1'b1, 8'hff, 64'h30, ATOMIC_NONE, observed, observed_err);
    do_cpu_request(ADDR_ATOMIC, 1'b0, 8'hff, 64'h40, ATOMIC_SC, observed, observed_err);
    check(observed === 64'h1, "SC.D succeeded after overlapping normal store");
    do_cpu_request(ADDR_ATOMIC, 1'b0, 8'hff, 64'h2, ATOMIC_ADD, observed, observed_err);
    check(observed === 64'h30, "AMOADD.D did not return pre-operation value");
    do_cpu_request(ADDR_ATOMIC, 1'b0, 8'hff, '0, ATOMIC_NONE, observed, observed_err);
    check(observed === 64'h32, "AMOADD.D did not update cached word");

    do_flush();
    expect_backing_word(ADDR_ATOMIC, 64'h32, "atomic dirty line was not written back by flush");

    // Zicbom maintains exactly the addressed 64-byte cache block.
    do_cpu_request(ADDR_A, 1'b1, 8'hff, 64'h1111_2222_3333_4444,
                   ATOMIC_NONE, observed, observed_err);
    expect_backing_word(ADDR_A, 64'h0102_0304_ffff_0708,
                        "CBO.CLEAN store leaked before maintenance");
    do_cbo(ADDR_A + 48'd24, CBO_CLEAN);
    expect_backing_word(ADDR_A, 64'h1111_2222_3333_4444,
                        "CBO.CLEAN did not write back its dirty line");

    do_cpu_request(ADDR_A, 1'b1, 8'hff, 64'haaaa_bbbb_cccc_dddd,
                   ATOMIC_NONE, observed, observed_err);
    do_cbo(ADDR_A + 48'd40, CBO_FLUSH);
    expect_backing_word(ADDR_A, 64'haaaa_bbbb_cccc_dddd,
                        "CBO.FLUSH did not write back its dirty line");
    set_backing_word(ADDR_A, 64'h0123_4567_89ab_cdef);
    do_cpu_request(ADDR_A, 1'b0, 8'hff, '0, ATOMIC_NONE, observed, observed_err);
    check(observed === 64'h0123_4567_89ab_cdef,
          "CBO.FLUSH did not invalidate the cleaned line");

    do_cpu_request(ADDR_A, 1'b1, 8'hff, 64'hfeed_face_cafe_beef,
                   ATOMIC_NONE, observed, observed_err);
    do_cbo(ADDR_A, CBO_INVAL);
    expect_backing_word(ADDR_A, 64'h0123_4567_89ab_cdef,
                        "CBO.INVAL unexpectedly wrote back a dirty line");
    do_cpu_request(ADDR_A, 1'b0, 8'hff, '0, ATOMIC_NONE, observed, observed_err);
    check(observed === 64'h0123_4567_89ab_cdef,
          "CBO.INVAL did not discard the cached dirty line");

    if (failures != 0)
      $fatal(1, "DCACHE FAIL: %0d checks failed", failures);
    $display("DCACHE PASS: 32KiB 2-way 64B physical D-Cache");
    $finish;
  end

endmodule
