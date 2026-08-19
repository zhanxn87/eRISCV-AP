// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// End-to-end AP first-stage boot regression. No DDR backdoor preload is used:
// reset fetch runs the Boot ROM, the ROM reads the BPI header/payload, writes
// DDR through D-Cache, executes FENCE.I, then the DDR payload records a marker.
module ap_soc_flash_boot_tb;
  import ap_soc_pkg::*;

  localparam logic [AP_PADDR_W-1:0] PAYLOAD_LOAD_ADDR = AP_DDR_BASE + 48'h1000;
  localparam logic [AP_PADDR_W-1:0] PAYLOAD_MARKER_ADDR = AP_DDR_BASE + 48'h2000;
  localparam logic [63:0] PAYLOAD_MARKER = 64'h5041_594c_4f41_4421;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic fetch_enable = 1'b0;
  logic [63:0] mtime = '0;
  logic [31:0] irq = '0;
  logic [AP_BPI_ADDR_W-1:0] bpi_addr;
  wire [AP_BPI_DATA_W-1:0] bpi_dq;
  logic bpi_ce_n;
  logic bpi_oe_n;
  logic bpi_we_n;
  logic bpi_adv_n;
  logic bpi_reset_n;
  logic bpi_ryby_n;
  logic [AP_BPI_ADDR_W-1:0] ignored_bpi_addr;
  wire [AP_BPI_DATA_W-1:0] ignored_bpi_dq;
  logic ignored_bpi_ce_n;
  logic ignored_bpi_oe_n;
  logic ignored_bpi_we_n;
  logic ignored_bpi_adv_n;
  logic ignored_bpi_reset_n;
  logic boot_ddr_write_seen;
  int unsigned bpi_read_cycles;
  logic [511:0] marker_line;

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) ddr_axi ();

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) bpi_axi ();

  ap_soc #(
    .BOOT_ROM_INIT_FILE_P("../../../sw/ap_bootrom/build/bootrom.mem"),
    .USE_EMBEDDED_BPI_NOR_P(1'b0)
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
    .bpi_addr_o(ignored_bpi_addr),
    .bpi_dq_io(ignored_bpi_dq),
    .bpi_ce_n_o(ignored_bpi_ce_n),
    .bpi_oe_n_o(ignored_bpi_oe_n),
    .bpi_we_n_o(ignored_bpi_we_n),
    .bpi_adv_n_o(ignored_bpi_adv_n),
    .bpi_reset_n_o(ignored_bpi_reset_n),
    .bpi_ryby_n_i(1'b1)
  );

  axi4_line_mem #(
    .PADDR_W_P(AP_PADDR_W),
    .AXI_DATA_W_P(AP_AXI_DATA_W),
    .AXI_ID_W_P(AP_AXI_SLV_ID_W),
    .SPARSE_P(1'b1)
  ) ddr_mem_i (
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_i(ddr_axi)
  );

  ap_axi_bpi_nor bpi_controller_i (
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_i(bpi_axi),
    .bpi_addr_o(bpi_addr),
    .bpi_dq_io(bpi_dq),
    .bpi_ce_n_o(bpi_ce_n),
    .bpi_oe_n_o(bpi_oe_n),
    .bpi_we_n_o(bpi_we_n),
    .bpi_adv_n_o(bpi_adv_n),
    .bpi_reset_n_o(bpi_reset_n),
    .bpi_ryby_n_i(bpi_ryby_n)
  );

  ap_bpi_nor_model #(
    .ADDR_W_P(AP_BPI_ADDR_W),
    .INIT_FILE_P("../../../sw/ap_bootrom/build/boot_payload.bpi.mem")
  ) bpi_nor_i (
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
      bpi_read_cycles <= 0;
      boot_ddr_write_seen <= 1'b0;
    end else begin
      if (!bpi_ce_n && !bpi_oe_n && bpi_we_n)
        bpi_read_cycles <= bpi_read_cycles + 1;
      if (ddr_axi.aw_valid && ddr_axi.aw_ready &&
          ddr_axi.aw_addr == PAYLOAD_LOAD_ADDR)
        boot_ddr_write_seen <= 1'b1;
    end
  end

  initial begin
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    fetch_enable = 1'b1;

    repeat (50000) begin
      @(posedge clk);
      ddr_mem_i.read_line(PAYLOAD_MARKER_ADDR, marker_line);
      if (marker_line[63:0] == PAYLOAD_MARKER) begin
        if (bpi_read_cycles < 24)
          $fatal(1, "boot did not perform expected BPI reads: %0d", bpi_read_cycles);
        if (!boot_ddr_write_seen)
          $fatal(1, "payload did not reach DDR through the D-Cache writeback path");
        $display("PASS: AP Boot ROM -> BPI NOR -> DDR -> payload execution");
        $finish;
      end
    end

    $fatal(1, "timeout waiting for payload DDR marker");
  end

endmodule
