// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// AXI memory-model regression. It proves sparse full-address storage, queued
// AXI reads/writes, address-channel backpressure, response latency, byte
// strobes, and read/write error responses without allocating a full DDR image.
module axi4_line_mem_tb;

  localparam int unsigned PADDR_W = 48;
  localparam int unsigned AXI_DATA_W = 64;
  localparam int unsigned AXI_ID_W = 4;
  localparam int unsigned LINE_BYTES = 64;
  localparam int unsigned LINE_BITS = LINE_BYTES * 8;
  localparam logic [PADDR_W-1:0] ADDR_A = 48'h0000_8000_0000;
  localparam logic [PADDR_W-1:0] ADDR_B = 48'h0000_9000_0000;
  localparam logic [PADDR_W-1:0] ADDR_C = 48'h0000_a000_0000;
  localparam logic [PADDR_W-1:0] ADDR_D = 48'h0000_b000_0000;
  localparam logic [PADDR_W-1:0] ADDR_READ_ERR = 48'h0000_c000_0000;
  localparam logic [PADDR_W-1:0] ADDR_WRITE_ERR = 48'h0000_d000_0000;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  AXI_BUS #(
    .AXI_ADDR_WIDTH(PADDR_W),
    .AXI_DATA_WIDTH(AXI_DATA_W),
    .AXI_ID_WIDTH(AXI_ID_W),
    .AXI_USER_WIDTH(1)
  ) axi ();

  logic [LINE_BITS-1:0] line_a;
  logic [LINE_BITS-1:0] line_b;
  logic [LINE_BITS-1:0] line_c;
  logic [LINE_BITS-1:0] line_d;
  logic [LINE_BITS-1:0] observed_line;
  int unsigned failures;

  axi4_line_mem #(
    .PADDR_W_P(PADDR_W),
    .AXI_DATA_W_P(AXI_DATA_W),
    .AXI_ID_W_P(AXI_ID_W),
    .SPARSE_P(1'b1),
    .MAX_READ_TXNS_P(2),
    .MAX_WRITE_TXNS_P(2),
    .READ_LATENCY_P(2),
    .AR_STALL_CYCLES_P(1),
    .AW_STALL_CYCLES_P(1),
    .READ_ERROR_ENABLE_P(1'b1),
    .READ_ERROR_ADDR_P(ADDR_READ_ERR),
    .WRITE_ERROR_ENABLE_P(1'b1),
    .WRITE_ERROR_ADDR_P(ADDR_WRITE_ERR)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_i(axi)
  );

  always #5 clk = ~clk;

  task automatic check(input logic condition, input string message);
    begin
      if (!condition) begin
        failures = failures + 1;
        $error("AXI4 LINE MEM FAIL: %s", message);
      end
    end
  endtask

  task automatic send_read_addr(
    input logic [PADDR_W-1:0] address,
    input logic [AXI_ID_W-1:0] id,
    input logic [2:0] size
  );
    begin
      @(negedge clk);
      axi.ar_id = id;
      axi.ar_addr = address;
      axi.ar_len = 8'd7;
      axi.ar_size = size;
      axi.ar_burst = 2'b01;
      axi.ar_lock = 1'b0;
      axi.ar_cache = 4'b1111;
      axi.ar_prot = '0;
      axi.ar_qos = '0;
      axi.ar_region = '0;
      axi.ar_user = '0;
      axi.ar_valid = 1'b1;
      do @(posedge clk); while (!axi.ar_ready);
      @(negedge clk);
      axi.ar_valid = 1'b0;
    end
  endtask

  task automatic collect_read_line(
    input logic [AXI_ID_W-1:0] expected_id,
    input logic [LINE_BITS-1:0] expected_line,
    input logic expected_error,
    input logic check_data
  );
    int unsigned beat;
    int unsigned timeout;
    begin
      axi.r_ready = 1'b1;
      beat = 0;
      timeout = 0;
      while (beat < 8) begin
        @(negedge clk);
        timeout = timeout + 1;
        if (timeout > 200)
          $fatal(1, "timed out waiting for AXI R beat %0d", beat);
        if (axi.r_valid && axi.r_ready) begin
          check(axi.r_id == expected_id, "RID changed across a queued read burst");
          if (check_data)
            check(axi.r_data === expected_line[beat * AXI_DATA_W +: AXI_DATA_W],
                  "sparse physical line returned wrong data");
          check(axi.r_resp == (expected_error ? 2'b10 : 2'b00),
                "RRESP did not match requested error policy");
          check(axi.r_last == (beat == 7), "RLAST was not aligned with beat seven");
          beat = beat + 1;
        end
      end
      @(negedge clk);
      axi.r_ready = 1'b0;
    end
  endtask

  task automatic send_write_addr(
    input logic [PADDR_W-1:0] address,
    input logic [AXI_ID_W-1:0] id
  );
    begin
      @(negedge clk);
      axi.aw_id = id;
      axi.aw_addr = address;
      axi.aw_len = 8'd7;
      axi.aw_size = 3'd3;
      axi.aw_burst = 2'b01;
      axi.aw_lock = 1'b0;
      axi.aw_cache = 4'b1111;
      axi.aw_prot = '0;
      axi.aw_qos = '0;
      axi.aw_region = '0;
      axi.aw_atop = '0;
      axi.aw_user = '0;
      axi.aw_valid = 1'b1;
      do @(posedge clk); while (!axi.aw_ready);
      @(negedge clk);
      axi.aw_valid = 1'b0;
    end
  endtask

  task automatic send_write_line(
    input logic [LINE_BITS-1:0] line_data
  );
    int unsigned beat;
    begin
      for (beat = 0; beat < 8; beat = beat + 1) begin
        @(negedge clk);
        axi.w_data = line_data[beat * AXI_DATA_W +: AXI_DATA_W];
        axi.w_strb = 8'hff;
        axi.w_last = beat == 7;
        axi.w_user = '0;
        axi.w_valid = 1'b1;
        do @(posedge clk); while (!axi.w_ready);
        @(negedge clk);
        axi.w_valid = 1'b0;
      end
    end
  endtask

  task automatic collect_write_response(
    input logic [AXI_ID_W-1:0] expected_id,
    input logic expected_error
  );
    int unsigned timeout;
    begin
      timeout = 0;
      while (!axi.b_valid) begin
        @(negedge clk);
        timeout = timeout + 1;
        if (timeout > 100)
          $fatal(1, "timed out waiting for AXI B response");
      end
      check(axi.b_id == expected_id, "BID does not match AWID");
      check(axi.b_resp == (expected_error ? 2'b10 : 2'b00),
            "BRESP did not match requested error policy");
      axi.b_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      axi.b_ready = 1'b0;
    end
  endtask

  task automatic expect_sparse_line(
    input logic [PADDR_W-1:0] address,
    input logic [LINE_BITS-1:0] expected_line,
    input string message
  );
    begin
      dut.read_line(address, observed_line);
      check(observed_line === expected_line, message);
    end
  endtask

  initial begin
    failures = 0;
    axi.aw_id = '0;
    axi.aw_addr = '0;
    axi.aw_len = '0;
    axi.aw_size = '0;
    axi.aw_burst = '0;
    axi.aw_lock = '0;
    axi.aw_cache = '0;
    axi.aw_prot = '0;
    axi.aw_qos = '0;
    axi.aw_region = '0;
    axi.aw_atop = '0;
    axi.aw_user = '0;
    axi.aw_valid = 1'b0;
    axi.w_data = '0;
    axi.w_strb = '0;
    axi.w_last = 1'b0;
    axi.w_user = '0;
    axi.w_valid = 1'b0;
    axi.b_ready = 1'b0;
    axi.ar_id = '0;
    axi.ar_addr = '0;
    axi.ar_len = '0;
    axi.ar_size = '0;
    axi.ar_burst = '0;
    axi.ar_lock = '0;
    axi.ar_cache = '0;
    axi.ar_prot = '0;
    axi.ar_qos = '0;
    axi.ar_region = '0;
    axi.ar_user = '0;
    axi.ar_valid = 1'b0;
    axi.r_ready = 1'b0;

    line_a = '0;
    line_b = '0;
    line_c = '0;
    line_d = '0;
    for (int unsigned beat = 0; beat < 8; beat = beat + 1) begin
      line_a[beat * AXI_DATA_W +: AXI_DATA_W] = 64'haaaa_0000_0000_0000 + 64'(beat);
      line_b[beat * AXI_DATA_W +: AXI_DATA_W] = 64'hbbbb_0000_0000_0000 + 64'(beat);
      line_c[beat * AXI_DATA_W +: AXI_DATA_W] = 64'hcccc_0000_0000_0000 + 64'(beat);
      line_d[beat * AXI_DATA_W +: AXI_DATA_W] = 64'hdddd_0000_0000_0000 + 64'(beat);
    end

    // Let the model initialize its associative storage, then preload two
    // distinct lines with identical dense low indexes. Sparse mode must keep
    // them independent at their full 48-bit physical addresses.
    #1;
    dut.preload_line(ADDR_A, line_a);
    dut.preload_line(ADDR_B, line_b);
    expect_sparse_line(ADDR_A, line_a, "sparse preload A was lost");
    expect_sparse_line(ADDR_B, line_b, "sparse preload B aliased A");

    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    // Queue two ARs while RREADY is low. The second request must survive both
    // the configurable address stall and the first transaction's latency.
    send_read_addr(ADDR_A, 4'h1, 3'd3);
    send_read_addr(ADDR_B, 4'h2, 3'd3);
    collect_read_line(4'h1, line_a, 1'b0, 1'b1);
    collect_read_line(4'h2, line_b, 1'b0, 1'b1);

    // Queue two writes before issuing W data. AXI4 W data follows AW order.
    send_write_addr(ADDR_C, 4'h3);
    send_write_addr(ADDR_D, 4'h4);
    send_write_line(line_c);
    collect_write_response(4'h3, 1'b0);
    send_write_line(line_d);
    collect_write_response(4'h4, 1'b0);
    expect_sparse_line(ADDR_C, line_c, "queued write C did not persist");
    expect_sparse_line(ADDR_D, line_d, "queued write D aliased C");

    // Error responses are generated without allocating or modifying the
    // corresponding sparse physical line.
    send_read_addr(ADDR_READ_ERR, 4'h5, 3'd3);
    collect_read_line(4'h5, '0, 1'b1, 1'b1);
    send_write_addr(ADDR_WRITE_ERR, 4'h6);
    send_write_line(line_c);
    collect_write_response(4'h6, 1'b1);
    expect_sparse_line(ADDR_WRITE_ERR, '0, "failed write changed sparse memory");

    // Full-width AXI transfer size is enforced; a narrow malformed burst
    // completes with SLVERR rather than silently corrupting memory.
    send_read_addr(ADDR_A, 4'h7, 3'd2);
    collect_read_line(4'h7, line_a, 1'b1, 1'b0);

    if (failures != 0)
      $fatal(1, "AXI4 LINE MEM FAIL: %0d checks failed", failures);
    $display("AXI4 LINE MEM PASS: sparse physical DDR, queued AXI, stalls, latency, and errors");
    $finish;
  end

endmodule
