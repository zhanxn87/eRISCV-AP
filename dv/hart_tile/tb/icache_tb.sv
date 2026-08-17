// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

module icache_tb;
  localparam int unsigned PADDR_W = 48;
  localparam logic [PADDR_W-1:0] ADDR0 = 48'h0000_8000_010c;
  localparam logic [PADDR_W-1:0] ADDR1 = 48'h0000_8000_0120;
  localparam logic [PADDR_W-1:0] ADDR2 = 48'h0000_8000_0208;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic cpu_req;
  logic [PADDR_W-1:0] cpu_addr;
  logic cpu_ready;
  logic cpu_rvalid;
  logic [31:0] cpu_rdata;
  logic line_req;
  logic [PADDR_W-1:0] line_addr;
  logic line_resp_valid;
  logic [511:0] line_rdata;
  logic line_err;
  logic invalidate;
  logic invalidate_done;
  integer line_request_count;
  integer failures;

  icache dut (
    .clk, .rst_n, .cpu_req_i(cpu_req), .cpu_addr_i(cpu_addr),
    .invalidate_i(invalidate), .invalidate_done_o(invalidate_done), .cpu_ready_o(cpu_ready), .cpu_rvalid_o(cpu_rvalid), .cpu_rdata_o(cpu_rdata),
    .line_req_o(line_req), .line_addr_o(line_addr), .line_resp_valid_i(line_resp_valid),
    .line_rdata_i(line_rdata), .line_err_i(line_err)
  );

  dcache_line_mem line_mem_i (
    .clk, .rst_n, .req_i(line_req), .we_i(1'b0), .addr_i(line_addr),
    .wdata_i('0), .resp_valid_o(line_resp_valid), .rdata_o(line_rdata), .err_o(line_err)
  );

  always #5 clk = ~clk;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      line_request_count <= 0;
    else if (line_req)
      line_request_count <= line_request_count + 1;
  end

  task automatic check(input logic condition, input string message);
    begin
      if (!condition) begin
        failures = failures + 1;
        $error("ICACHE FAIL: %s", message);
      end
    end
  endtask

  task automatic invalidate_all;
    begin
      @(negedge clk);
      invalidate = 1'b1;
      do @(posedge clk); while (!invalidate_done);
      @(negedge clk);
      invalidate = 1'b0;
    end
  endtask

  task automatic fetch_word(
    input logic [PADDR_W-1:0] addr,
    output logic [31:0] data
  );
    int unsigned timeout;
    begin
      while (!cpu_ready) @(posedge clk);
      @(negedge clk);
      cpu_addr = addr;
      cpu_req = 1'b1;
      @(negedge clk);
      cpu_req = 1'b0;
      timeout = 0;
      do begin
        @(posedge clk);
        timeout = timeout + 1;
        if (timeout > 80)
          $fatal(1, "ICACHE fetch timeout state=%0d", dut.state_q);
      end while (!cpu_rvalid);
      data = cpu_rdata;
      @(negedge clk);
    end
  endtask

  initial begin
    logic [31:0] fetched;
    cpu_req = 1'b0;
    cpu_addr = '0;
    invalidate = 1'b0;
    failures = 0;
    line_mem_i.mem[14'h0004] = '0;
    line_mem_i.mem[14'h0004][3 * 32 +: 32] = 32'hdead_beef;
    line_mem_i.mem[14'h0004][8 * 32 +: 32] = 32'h1234_5678;
    line_mem_i.mem[14'h0008] = '0;
    line_mem_i.mem[14'h0008][2 * 32 +: 32] = 32'hca11_ab1e;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    fetch_word(ADDR0, fetched);
    check(fetched == 32'hdead_beef, "miss refill returned wrong word");
    check(line_request_count == 1, "first fetch must issue one line refill");

    fetch_word(ADDR1, fetched);
    check(fetched == 32'h1234_5678, "same-line hit returned wrong word");
    check(line_request_count == 1, "same-line fetch must not refill");

    invalidate_all();
    fetch_word(ADDR0, fetched);
    check(fetched == 32'hdead_beef, "post-invalidate refill returned wrong word");
    check(line_request_count == 2, "invalidate must force a refill");

    fetch_word(ADDR2, fetched);
    check(fetched == 32'hca11_ab1e, "second-line refill returned wrong word");
    check(line_request_count == 3, "second line must issue one additional refill");

    if (failures != 0)
      $fatal(1, "ICACHE failed with %0d errors", failures);
    $display("ICACHE PASS: 32KiB 2-way 64B physical instruction cache");
    $finish;
  end
endmodule
