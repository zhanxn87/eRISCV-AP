// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

module cache_axi4_line_adapter_tb;

  localparam int unsigned PADDR_W = 48;
  localparam int unsigned AXI_DATA_W = 64;
  localparam int unsigned AXI_ID_W = 4;
  localparam int unsigned LINE_BYTES = 64;
  localparam int unsigned LINE_BITS = LINE_BYTES * 8;
  localparam logic [PADDR_W-1:0] READ_ADDR = 48'h0000_0000_0100;
  localparam logic [PADDR_W-1:0] WRITE_ADDR = 48'h0000_0000_0200;
  localparam logic [PADDR_W-1:0] ERR_READ_ADDR = 48'h0000_0000_0400;
  localparam logic [PADDR_W-1:0] ERR_WRITE_ADDR = 48'h0000_0000_0500;

  logic clk;
  logic rst_n;
  logic line_req;
  logic line_we;
  logic [PADDR_W-1:0] line_addr;
  logic [LINE_BITS-1:0] line_wdata;
  logic line_resp_valid;
  logic [LINE_BITS-1:0] line_rdata;
  logic line_err;

  AXI_BUS #(
    .AXI_ADDR_WIDTH(PADDR_W),
    .AXI_DATA_WIDTH(AXI_DATA_W),
    .AXI_ID_WIDTH(AXI_ID_W),
    .AXI_USER_WIDTH(1)
  ) axi ();

  logic [63:0] ram [0:255];
  logic read_active_q;
  logic [PADDR_W-1:0] read_addr_q;
  logic [3:0] read_beat_q;
  logic [1:0] read_delay_q;
  logic write_active_q;
  logic [PADDR_W-1:0] write_addr_q;
  logic [3:0] write_beat_q;
  logic b_pending_q;
  logic [PADDR_W-1:0] b_addr_q;
  logic [1:0] b_delay_q;
  logic [7:0] cycle_q;
  integer ar_count;
  integer aw_count;
  integer r_count;
  integer w_count;
  integer failures;
  integer ram_index;
  integer byte_lane;

  cache_axi4_line_adapter #(
    .PADDR_W_P(PADDR_W),
    .AXI_DATA_W_P(AXI_DATA_W),
    .AXI_ID_W_P(AXI_ID_W),
    .LINE_BYTES_P(LINE_BYTES)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .line_req_i(line_req),
    .line_we_i(line_we),
    .line_addr_i(line_addr),
    .line_wdata_i(line_wdata),
    .line_resp_valid_o(line_resp_valid),
    .line_rdata_o(line_rdata),
    .line_err_o(line_err),
    .m_axi_o(axi)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic check(input logic condition, input string message);
    begin
      if (!condition) begin
        failures = failures + 1;
        $error("CACHE AXI FAIL: %s", message);
      end
    end
  endtask

  task automatic do_line_request(
    input logic write_enable,
    input logic [PADDR_W-1:0] address,
    input logic [LINE_BITS-1:0] write_data,
    output logic [LINE_BITS-1:0] read_data,
    output logic got_error
  );
    int unsigned timeout_cycles;
    begin
      @(negedge clk);
      line_addr = address;
      line_we = write_enable;
      line_wdata = write_data;
      line_req = 1'b1;
      @(negedge clk);
      line_req = 1'b0;
      timeout_cycles = 0;
      do begin
        @(posedge clk);
        #1;
        timeout_cycles = timeout_cycles + 1;
        if (timeout_cycles > 200)
          $fatal(1, "CACHE AXI request timeout state=%0d", dut.state_q);
      end while (!line_resp_valid);
      read_data = line_rdata;
      got_error = line_err;
      @(negedge clk);
    end
  endtask

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      axi.ar_ready <= 1'b0;
      axi.aw_ready <= 1'b0;
      axi.w_ready <= 1'b0;
      axi.r_id <= '0;
      axi.r_data <= '0;
      axi.r_resp <= 2'b00;
      axi.r_last <= 1'b0;
      axi.r_user <= '0;
      axi.r_valid <= 1'b0;
      axi.b_id <= '0;
      axi.b_resp <= 2'b00;
      axi.b_user <= '0;
      axi.b_valid <= 1'b0;
      read_active_q <= 1'b0;
      read_addr_q <= '0;
      read_beat_q <= '0;
      read_delay_q <= '0;
      write_active_q <= 1'b0;
      write_addr_q <= '0;
      write_beat_q <= '0;
      b_pending_q <= 1'b0;
      b_addr_q <= '0;
      b_delay_q <= '0;
      cycle_q <= '0;
      ar_count <= 0;
      aw_count <= 0;
      r_count <= 0;
      w_count <= 0;
    end else begin
      cycle_q <= cycle_q + 1'b1;
      // Deterministic independent backpressure on all request channels.
      axi.ar_ready <= cycle_q[0];
      axi.aw_ready <= cycle_q[1];
      axi.w_ready <= cycle_q[0] | cycle_q[1];

      if (axi.ar_valid && axi.ar_ready) begin
        ar_count <= ar_count + 1;
        check(axi.ar_id == '0 && axi.ar_len == 8'd7 && axi.ar_size == 3'd3 &&
              axi.ar_burst == 2'b01 && axi.ar_cache == 4'b1111 &&
              axi.ar_addr[5:0] == '0, "invalid AXI read burst attributes");
        read_active_q <= 1'b1;
        read_addr_q <= axi.ar_addr;
        read_beat_q <= '0;
        read_delay_q <= 2'd2;
      end

      if (axi.r_valid && axi.r_ready) begin
        r_count <= r_count + 1;
        axi.r_valid <= 1'b0;
        if (axi.r_last)
          read_active_q <= 1'b0;
        else begin
          read_beat_q <= read_beat_q + 1'b1;
          read_delay_q <= 2'd1;
        end
      end else if (!axi.r_valid && read_active_q) begin
        if (read_delay_q != 0) begin
          read_delay_q <= read_delay_q - 1'b1;
        end else begin
          axi.r_valid <= 1'b1;
          axi.r_id <= '0;
          axi.r_data <= ram[read_addr_q[10:3] + 8'(read_beat_q)];
          axi.r_resp <= (read_addr_q == ERR_READ_ADDR && read_beat_q == 4'd3) ? 2'b10 : 2'b00;
          axi.r_last <= read_beat_q == 4'd7;
        end
      end

      if (axi.aw_valid && axi.aw_ready) begin
        aw_count <= aw_count + 1;
        check(axi.aw_id == '0 && axi.aw_len == 8'd7 && axi.aw_size == 3'd3 &&
              axi.aw_burst == 2'b01 && axi.aw_cache == 4'b1111 &&
              axi.aw_addr[5:0] == '0, "invalid AXI write burst attributes");
        write_active_q <= 1'b1;
        write_addr_q <= axi.aw_addr;
        write_beat_q <= '0;
      end

      if (axi.w_valid && axi.w_ready) begin
        w_count <= w_count + 1;
        check(write_active_q, "AXI W beat arrived before an AW handshake");
        check(axi.w_strb == 8'hff, "cache writeback did not enable every byte");
        for (byte_lane = 0; byte_lane < 8; byte_lane = byte_lane + 1)
          if (axi.w_strb[byte_lane])
            ram[write_addr_q[10:3] + 8'(write_beat_q)][byte_lane * 8 +: 8] <=
                axi.w_data[byte_lane * 8 +: 8];
        if (axi.w_last) begin
          check(write_beat_q == 4'd7, "AXI WLAST was not on beat seven");
          write_active_q <= 1'b0;
          b_pending_q <= 1'b1;
          b_addr_q <= write_addr_q;
          b_delay_q <= 2'd2;
        end else begin
          check(write_beat_q != 4'd7, "missing AXI WLAST on beat seven");
          write_beat_q <= write_beat_q + 1'b1;
        end
      end

      if (axi.b_valid && axi.b_ready) begin
        axi.b_valid <= 1'b0;
      end else if (!axi.b_valid && b_pending_q) begin
        if (b_delay_q != 0) begin
          b_delay_q <= b_delay_q - 1'b1;
        end else begin
          axi.b_valid <= 1'b1;
          axi.b_id <= '0;
          axi.b_resp <= (b_addr_q == ERR_WRITE_ADDR) ? 2'b10 : 2'b00;
          b_pending_q <= 1'b0;
        end
      end
    end
  end

  logic [LINE_BITS-1:0] observed_line;
  logic [LINE_BITS-1:0] write_line;
  logic observed_err;
  integer word_index;

  initial begin
    failures = 0;
    line_req = 1'b0;
    line_we = 1'b0;
    line_addr = '0;
    line_wdata = '0;
    rst_n = 1'b0;
    for (ram_index = 0; ram_index < 256; ram_index = ram_index + 1)
      ram[ram_index] = '0;
    for (word_index = 0; word_index < 8; word_index = word_index + 1)
      ram[READ_ADDR[10:3] + 8'(word_index)] = 64'h1111_0000_0000_0000 + 64'(word_index);
    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    do_line_request(1'b0, READ_ADDR + 48'd24, '0, observed_line, observed_err);
    check(!observed_err, "read burst returned an unexpected error");
    for (word_index = 0; word_index < 8; word_index = word_index + 1)
      check(observed_line[word_index * 64 +: 64] ==
            (64'h1111_0000_0000_0000 + 64'(word_index)),
            "read burst assembled incorrect cache-line data");

    for (word_index = 0; word_index < 8; word_index = word_index + 1)
      write_line[word_index * 64 +: 64] = 64'haaaa_0000_0000_0000 + 64'(word_index);
    do_line_request(1'b1, WRITE_ADDR + 48'd16, write_line, observed_line, observed_err);
    check(!observed_err, "write burst returned an unexpected error");
    for (word_index = 0; word_index < 8; word_index = word_index + 1)
      check(ram[WRITE_ADDR[10:3] + 8'(word_index)] ==
            (64'haaaa_0000_0000_0000 + 64'(word_index)),
            "write burst did not update the expected backing-memory beat");

    do_line_request(1'b0, ERR_READ_ADDR, '0, observed_line, observed_err);
    check(observed_err, "AXI RRESP error was not propagated to cache");
    do_line_request(1'b1, ERR_WRITE_ADDR, write_line, observed_line, observed_err);
    check(observed_err, "AXI BRESP error was not propagated to cache");
    check(ar_count == 2 && aw_count == 2, "unexpected AXI address transaction count");
    check(r_count == 16 && w_count == 16, "unexpected AXI data beat count");

    if (failures != 0)
      $fatal(1, "CACHE AXI FAIL: %0d checks failed", failures);
    $display("CACHE AXI PASS: 64-bit 8-beat line transport with backpressure and errors");
    $finish;
  end

endmodule
