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

  logic [AXI_ID_W-1:0] axi_awid;
  logic [PADDR_W-1:0] axi_awaddr;
  logic [7:0] axi_awlen;
  logic [2:0] axi_awsize;
  logic [1:0] axi_awburst;
  logic [3:0] axi_awcache;
  logic axi_awvalid;
  logic axi_awready;
  logic [AXI_DATA_W-1:0] axi_wdata;
  logic [AXI_DATA_W/8-1:0] axi_wstrb;
  logic axi_wlast;
  logic axi_wvalid;
  logic axi_wready;
  logic [AXI_ID_W-1:0] axi_bid;
  logic [1:0] axi_bresp;
  logic axi_bvalid;
  logic axi_bready;
  logic [AXI_ID_W-1:0] axi_arid;
  logic [PADDR_W-1:0] axi_araddr;
  logic [7:0] axi_arlen;
  logic [2:0] axi_arsize;
  logic [1:0] axi_arburst;
  logic [3:0] axi_arcache;
  logic axi_arvalid;
  logic axi_arready;
  logic [AXI_ID_W-1:0] axi_rid;
  logic [AXI_DATA_W-1:0] axi_rdata;
  logic [1:0] axi_rresp;
  logic axi_rlast;
  logic axi_rvalid;
  logic axi_rready;

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
    .clk(clk), .rst_n(rst_n),
    .line_req_i(line_req), .line_we_i(line_we), .line_addr_i(line_addr),
    .line_wdata_i(line_wdata), .line_resp_valid_o(line_resp_valid),
    .line_rdata_o(line_rdata), .line_err_o(line_err),
    .m_axi_awid_o(axi_awid), .m_axi_awaddr_o(axi_awaddr),
    .m_axi_awlen_o(axi_awlen), .m_axi_awsize_o(axi_awsize),
    .m_axi_awburst_o(axi_awburst), .m_axi_awcache_o(axi_awcache),
    .m_axi_awvalid_o(axi_awvalid), .m_axi_awready_i(axi_awready),
    .m_axi_wdata_o(axi_wdata), .m_axi_wstrb_o(axi_wstrb),
    .m_axi_wlast_o(axi_wlast), .m_axi_wvalid_o(axi_wvalid),
    .m_axi_wready_i(axi_wready),
    .m_axi_bid_i(axi_bid), .m_axi_bresp_i(axi_bresp),
    .m_axi_bvalid_i(axi_bvalid), .m_axi_bready_o(axi_bready),
    .m_axi_arid_o(axi_arid), .m_axi_araddr_o(axi_araddr),
    .m_axi_arlen_o(axi_arlen), .m_axi_arsize_o(axi_arsize),
    .m_axi_arburst_o(axi_arburst), .m_axi_arcache_o(axi_arcache),
    .m_axi_arvalid_o(axi_arvalid), .m_axi_arready_i(axi_arready),
    .m_axi_rid_i(axi_rid), .m_axi_rdata_i(axi_rdata),
    .m_axi_rresp_i(axi_rresp), .m_axi_rlast_i(axi_rlast),
    .m_axi_rvalid_i(axi_rvalid), .m_axi_rready_o(axi_rready)
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
      axi_arready <= 1'b0;
      axi_awready <= 1'b0;
      axi_wready <= 1'b0;
      axi_rid <= '0;
      axi_rdata <= '0;
      axi_rresp <= 2'b00;
      axi_rlast <= 1'b0;
      axi_rvalid <= 1'b0;
      axi_bid <= '0;
      axi_bresp <= 2'b00;
      axi_bvalid <= 1'b0;
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
      axi_arready <= cycle_q[0];
      axi_awready <= cycle_q[1];
      axi_wready <= cycle_q[0] | cycle_q[1];

      if (axi_arvalid && axi_arready) begin
        ar_count <= ar_count + 1;
        check(axi_arid == '0 && axi_arlen == 8'd7 && axi_arsize == 3'd3 &&
              axi_arburst == 2'b01 && axi_arcache == 4'b1111 &&
              axi_araddr[5:0] == '0, "invalid AXI read burst attributes");
        read_active_q <= 1'b1;
        read_addr_q <= axi_araddr;
        read_beat_q <= '0;
        read_delay_q <= 2'd2;
      end

      if (axi_rvalid && axi_rready) begin
        r_count <= r_count + 1;
        axi_rvalid <= 1'b0;
        if (axi_rlast)
          read_active_q <= 1'b0;
        else begin
          read_beat_q <= read_beat_q + 1'b1;
          read_delay_q <= 2'd1;
        end
      end else if (!axi_rvalid && read_active_q) begin
        if (read_delay_q != 0) begin
          read_delay_q <= read_delay_q - 1'b1;
        end else begin
          axi_rvalid <= 1'b1;
          axi_rid <= '0;
          axi_rdata <= ram[read_addr_q[10:3] + 8'(read_beat_q)];
          axi_rresp <= (read_addr_q == ERR_READ_ADDR && read_beat_q == 4'd3) ? 2'b10 : 2'b00;
          axi_rlast <= read_beat_q == 4'd7;
        end
      end

      if (axi_awvalid && axi_awready) begin
        aw_count <= aw_count + 1;
        check(axi_awid == '0 && axi_awlen == 8'd7 && axi_awsize == 3'd3 &&
              axi_awburst == 2'b01 && axi_awcache == 4'b1111 &&
              axi_awaddr[5:0] == '0, "invalid AXI write burst attributes");
        write_active_q <= 1'b1;
        write_addr_q <= axi_awaddr;
        write_beat_q <= '0;
      end

      if (axi_wvalid && axi_wready) begin
        w_count <= w_count + 1;
        check(write_active_q, "AXI W beat arrived before an AW handshake");
        check(axi_wstrb == 8'hff, "cache writeback did not enable every byte");
        for (byte_lane = 0; byte_lane < 8; byte_lane = byte_lane + 1)
          if (axi_wstrb[byte_lane])
            ram[write_addr_q[10:3] + 8'(write_beat_q)][byte_lane * 8 +: 8] <=
                axi_wdata[byte_lane * 8 +: 8];
        if (axi_wlast) begin
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

      if (axi_bvalid && axi_bready) begin
        axi_bvalid <= 1'b0;
      end else if (!axi_bvalid && b_pending_q) begin
        if (b_delay_q != 0) begin
          b_delay_q <= b_delay_q - 1'b1;
        end else begin
          axi_bvalid <= 1'b1;
          axi_bid <= '0;
          axi_bresp <= (b_addr_q == ERR_WRITE_ADDR) ? 2'b10 : 2'b00;
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
