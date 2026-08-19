// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// Focused AP peripheral subsystem regression: AXI-to-APB splitting,
// CLINT/PLIC APB accesses, APB GPIO, BPI routing, and DECERR fallback.
module ap_peripheral_subsystem_tb;
  import ap_soc_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic eth_irq = 1'b0;
  logic uart_rx = 1'b1;
  logic uart_tx;
  logic [31:0] gpio_i = 32'h5a5a_c3c3;
  logic [31:0] gpio_o;
  logic [31:0] gpio_oe;
  logic spi_miso = 1'b0;
  logic spi_sclk;
  logic spi_mosi;
  logic [3:0] spi_ss;
  logic [63:0] mtime;
  logic msip;
  logic mtip;
  logic meip;
  logic seip;
  logic clint_apb_seen;
  logic plic_apb_seen;
  logic eth_apb_seen;
  logic eth_psel;
  logic eth_penable;
  logic eth_pwrite;
  logic [AP_PADDR_W-1:0] eth_paddr;
  logic [31:0] eth_pwdata;
  logic [3:0] eth_pstrb;
  logic eth_pready = 1'b1;
  logic [31:0] eth_prdata = 32'h0;
  logic eth_pslverr = 1'b0;
  logic [AP_BPI_ADDR_W-1:0] bpi_addr;
  wire [AP_BPI_DATA_W-1:0] bpi_dq;
  logic bpi_ce_n;
  logic bpi_oe_n;
  logic bpi_we_n;
  logic bpi_adv_n;
  logic bpi_reset_n;
  logic bpi_ryby_n;

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) axi ();
  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) bpi_axi ();
  ap_peripheral_subsystem dut (
    .clk(clk),
    .rst_n(rst_n),
    .eth_irq_i(eth_irq),
    .uart_rx_i(uart_rx),
    .uart_tx_o(uart_tx),
    .gpio_i(gpio_i),
    .gpio_o(gpio_o),
    .gpio_oe_o(gpio_oe),
    .spi_miso_i(spi_miso),
    .spi_sclk_o(spi_sclk),
    .spi_mosi_o(spi_mosi),
    .spi_ss_o(spi_ss),
    .mtime_o(mtime),
    .msip_o(msip),
    .mtip_o(mtip),
    .meip_o(meip),
    .seip_o(seip),
    .eth_psel_o(eth_psel),
    .eth_penable_o(eth_penable),
    .eth_pwrite_o(eth_pwrite),
    .eth_paddr_o(eth_paddr),
    .eth_pwdata_o(eth_pwdata),
    .eth_pstrb_o(eth_pstrb),
    .eth_pready_i(eth_pready),
    .eth_prdata_i(eth_prdata),
    .eth_pslverr_i(eth_pslverr),
    .periph_axi_i(axi),
    .bpi_axi_o(bpi_axi),
    .bpi_addr_o(bpi_addr),
    .bpi_dq_io(bpi_dq),
    .bpi_ce_n_o(bpi_ce_n),
    .bpi_oe_n_o(bpi_oe_n),
    .bpi_we_n_o(bpi_we_n),
    .bpi_adv_n_o(bpi_adv_n),
    .bpi_reset_n_o(bpi_reset_n),
    .bpi_ryby_n_i(bpi_ryby_n)
  );

  ap_bpi_nor_model bpi_nor_i (
    .reset_n_i(bpi_reset_n),
    .addr_i(bpi_addr),
    .dq_io(bpi_dq),
    .ce_n_i(bpi_ce_n),
    .oe_n_i(bpi_oe_n),
    .we_n_i(bpi_we_n),
    .adv_n_i(bpi_adv_n),
    .ryby_n_o(bpi_ryby_n)
  );

  always #5 clk = ~clk;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      clint_apb_seen <= 1'b0;
      plic_apb_seen <= 1'b0;
      eth_apb_seen <= 1'b0;
    end else begin
      if (dut.apb_psel && dut.apb_penable && dut.clint_psel)
        clint_apb_seen <= 1'b1;
      if (dut.apb_psel && dut.apb_penable && dut.plic_psel)
        plic_apb_seen <= 1'b1;
      if (dut.apb_psel && dut.apb_penable && eth_psel)
        eth_apb_seen <= 1'b1;
    end
  end

  task automatic wait_for_aw;
    begin
      while (!axi.aw_ready)
        @(negedge clk);
      @(posedge clk);
      #1;
    end
  endtask

  task automatic wait_for_w;
    begin
      while (!axi.w_ready)
        @(negedge clk);
      @(posedge clk);
      #1;
    end
  endtask

  task automatic wait_for_b;
    begin
      while (!axi.b_valid)
        @(negedge clk);
      if (axi.b_id != 4'd3 || axi.b_resp != 2'b00)
        $fatal(1, "AXI write response failed: id=%h resp=%h", axi.b_id, axi.b_resp);
      @(posedge clk);
      #1;
    end
  endtask

  task automatic wait_for_ar;
    begin
      while (!axi.ar_ready)
        @(negedge clk);
      @(posedge clk);
      #1;
    end
  endtask

  task automatic wait_for_r(
    input logic [63:0] expected,
    input logic [1:0] expected_resp
  );
    begin
      while (!axi.r_valid)
        @(negedge clk);
      if (axi.r_id != 4'd3 || axi.r_resp != expected_resp || !axi.r_last ||
          (expected_resp == 2'b00 && axi.r_data != expected))
        $fatal(1, "AXI read response failed: data=%h id=%h resp=%h",
               axi.r_data, axi.r_id, axi.r_resp);
      @(posedge clk);
      #1;
    end
  endtask

  task automatic axi_write64(
    input logic [AP_PADDR_W-1:0] addr,
    input logic [63:0] data,
    input logic [7:0] strb
  );
    begin
      @(negedge clk);
      axi.aw_id = 4'd3;
      axi.aw_addr = addr;
      axi.aw_len = 8'd0;
      axi.aw_size = 3'd3;
      axi.aw_burst = 2'b01;
      axi.aw_lock = 1'b0;
      axi.aw_cache = 4'b0000;
      axi.aw_prot = '0;
      axi.aw_qos = '0;
      axi.aw_region = '0;
      axi.aw_atop = '0;
      axi.aw_user = '0;
      axi.aw_valid = 1'b1;
      wait_for_aw();
      axi.aw_valid = 1'b0;
      axi.w_data = data;
      axi.w_strb = strb;
      axi.w_last = 1'b1;
      axi.w_user = '0;
      axi.w_valid = 1'b1;
      wait_for_w();
      axi.w_valid = 1'b0;
      axi.b_ready = 1'b1;
      wait_for_b();
      axi.b_ready = 1'b0;
    end
  endtask

  task automatic axi_read64(
    input logic [AP_PADDR_W-1:0] addr,
    input logic [63:0] expected,
    input logic [1:0] expected_resp
  );
    begin
      @(negedge clk);
      axi.ar_id = 4'd3;
      axi.ar_addr = addr;
      axi.ar_len = 8'd0;
      axi.ar_size = 3'd3;
      axi.ar_burst = 2'b01;
      axi.ar_lock = 1'b0;
      axi.ar_cache = 4'b0000;
      axi.ar_prot = '0;
      axi.ar_qos = '0;
      axi.ar_region = '0;
      axi.ar_user = '0;
      axi.ar_valid = 1'b1;
      wait_for_ar();
      axi.ar_valid = 1'b0;
      axi.r_ready = 1'b1;
      wait_for_r(expected, expected_resp);
      axi.r_ready = 1'b0;
    end
  endtask

  initial begin
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
    bpi_nor_i.preload_word(26'd0, 16'h0001);
    bpi_nor_i.preload_word(26'd1, 16'h0000);
    bpi_nor_i.preload_word(26'd2, 16'h0000);
    bpi_nor_i.preload_word(26'd3, 16'hb001);

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (3) @(posedge clk);

    axi_write64(AP_CLINT_BASE, 64'h0000_0000_0000_0001, 8'h0f);
    if (!msip)
      $fatal(1, "CLINT MSIP did not assert");
    axi_write64(AP_CLINT_BASE + 48'h4000, 64'h0000_0000_0000_0000, 8'hff);
    repeat (2) @(posedge clk);
    if (!mtip || mtime == '0 || !clint_apb_seen)
      $fatal(1, "CLINT APB MTIP/MTIME path failed");

    axi_write64(AP_GPIO0_BASE, 64'h0000_0000_0000_00a5, 8'h0f);
    axi_write64(AP_GPIO0_BASE + 48'h8, 64'h0000_0000_0000_00ff, 8'h0f);
    if (gpio_o != 32'h0000_00a5 || gpio_oe != 32'h0000_00ff)
      $fatal(1, "APB GPIO write path failed: out=%h oe=%h", gpio_o, gpio_oe);
    axi_read64(AP_GPIO0_BASE, {gpio_i, 32'h0000_00a5}, 2'b00);
    axi_read64(AP_ETH0_BASE, 64'h0, 2'b00);
    if (!eth_apb_seen)
      $fatal(1, "Ethernet APB decode path failed");

    axi_write64(AP_PLIC_BASE, 64'h0000_0001_0000_0000, 8'hf0);
    axi_write64(AP_PLIC_BASE + 48'h2000, 64'h0000_0000_0000_0002, 8'h0f);
    axi_write64(AP_PLIC_BASE + 48'h2080, 64'h0000_0000_0000_0002, 8'h0f);
    axi_write64(AP_UART0_BASE + 48'h10, 64'h0000_0000_0000_0008, 8'h0f);
    repeat (3) @(posedge clk);
    if (!meip || !seip || !plic_apb_seen)
      $fatal(1, "PLIC APB M/S contexts did not receive the UART source");

    axi_read64(AP_BPI_BASE, 64'hb001_0000_0000_0001, 2'b00);
    axi_read64(AP_BPI_LIMIT, 64'h0, 2'b11);
    $display("PASS: AP peripheral subsystem CLINT/PLIC/APB/Ethernet/BPI/DECERR integration");
    $finish;
  end

endmodule
