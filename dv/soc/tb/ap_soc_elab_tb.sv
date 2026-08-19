// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// AP top-level routing smoke test.  A tiny Boot ROM program transfers fetch
// to AP_DDR_BASE; the test then observes the resulting 64-byte I-Cache fill on
// axi_mem/DDR.  Focused cache testbenches still cover cache transaction detail.
module ap_soc_elab_tb;
  import ap_soc_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic fetch_enable = 1'b0;
  logic ddr_read_seen;
  logic [63:0] mtime = '0;
  logic [31:0] irq = '0;

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W), .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W), .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) ddr_axi ();

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) bpi_axi ();

  logic [AP_BPI_ADDR_W-1:0] bpi_addr;
  wire [AP_BPI_DATA_W-1:0] bpi_dq;
  logic bpi_ce_n;
  logic bpi_oe_n;
  logic bpi_we_n;
  logic bpi_adv_n;
  logic bpi_reset_n;
  logic bpi_ryby_n = 1'b1;
  ap_soc #(
    .BOOT_ROM_INIT_FILE_P("../tb/ap_soc_ddr_boot.mem")
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .fetch_enable_i(fetch_enable),
    .mtime_i(mtime),
    .irq_i(irq),
    .uart_rx_i(1'b1),
    .uart_tx_o(),
    .gpio_i('0),
    .gpio_o(),
    .gpio_oe_o(),
    .spi_miso_i(1'b0),
    .spi_sclk_o(),
    .spi_mosi_o(),
    .spi_ss_o(),
    .eth_rx_clk_i(clk),
    .eth_rx_rst_n_i(rst_n),
    .eth_gmii_rxd_i(8'h00),
    .eth_gmii_rx_dv_i(1'b0),
    .eth_gmii_rx_er_i(1'b0),
    .eth_tx_clk_i(clk),
    .eth_tx_rst_n_i(rst_n),
    .eth_gmii_clk_enable_i(1'b1),
    .eth_gmii_txd_o(),
    .eth_gmii_tx_en_o(),
    .eth_gmii_tx_er_o(),
    .debug_halt_req_i(1'b0),
    .debug_resume_req_i(1'b0),
    .debug_halted_o(),
    .debug_running_o(),
    .debug_pc_o(),
    .debug_cause_o(),
    .ddr_axi_o(ddr_axi),
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

  axi4_line_mem #(
    .PADDR_W_P(AP_PADDR_W), .AXI_DATA_W_P(AP_AXI_DATA_W),
    .AXI_ID_W_P(AP_AXI_SLV_ID_W)
  ) ddr_mem_i (
    .clk     (clk),
    .rst_n   (rst_n),
    .s_axi_i(ddr_axi)
  );

  // BPI pins are intentionally idle in this DDR-routing-only smoke.

  always #5 clk = ~clk;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ddr_read_seen <= 1'b0;
    end else if (ddr_axi.ar_valid && ddr_axi.ar_ready) begin
      if (ddr_axi.ar_addr != AP_DDR_BASE)
        $fatal(1, "unexpected DDR read address: %h", ddr_axi.ar_addr);
      if (ddr_axi.ar_len != 8'd7 || ddr_axi.ar_size != 3'd3 ||
          ddr_axi.ar_burst != 2'b01)
        $fatal(1, "I-Cache fill is not an 8-beat 64-bit INCR burst");
      ddr_read_seen <= 1'b1;
    end
  end

  initial begin
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    fetch_enable = 1'b1;
    repeat (300) begin
      @(posedge clk);
      if (ddr_read_seen) begin
        $display("PASS: AP SoC Boot ROM -> I-Cache -> axi_mem -> DDR routing");
        $finish;
      end
    end
    $fatal(1, "timeout waiting for I-Cache DDR line read");
  end
endmodule
