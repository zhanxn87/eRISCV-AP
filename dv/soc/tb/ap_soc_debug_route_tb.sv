// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// SoC-level external debug routing. Halt is sampled at an instruction boundary,
// retained while halted, then resume restarts fetch at the saved DPC.
module ap_soc_debug_route_tb;
  import ap_soc_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic fetch_enable = 1'b0;
  logic [63:0] mtime = '0;
  logic [31:0] irq = '0;
  logic debug_halt_req = 1'b0;
  logic debug_resume_req = 1'b0;
  logic debug_halted;
  logic debug_running;
  logic [63:0] debug_pc;
  logic [2:0] debug_cause;
  logic [63:0] halted_pc;

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) ddr_axi ();

  logic [AP_BPI_ADDR_W-1:0] bpi_addr;
  wire [AP_BPI_DATA_W-1:0] bpi_dq;
  logic bpi_ce_n;
  logic bpi_oe_n;
  logic bpi_we_n;
  logic bpi_reset_n;
  logic bpi_ryby_n = 1'b1;
  ap_soc dut (
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
    .eth_gmii_txd_o(),
    .eth_gmii_tx_en_o(),
    .eth_gmii_tx_er_o(),
    .debug_halt_req_i(debug_halt_req),
    .debug_resume_req_i(debug_resume_req),
    .debug_halted_o(debug_halted),
    .debug_running_o(debug_running),
    .debug_pc_o(debug_pc),
    .debug_cause_o(debug_cause),
    .ddr_axi_o(ddr_axi),
    .bpi_addr_o(bpi_addr),
    .bpi_dq_io(bpi_dq),
    .bpi_ce_n_o(bpi_ce_n),
    .bpi_oe_n_o(bpi_oe_n),
    .bpi_we_n_o(bpi_we_n),
    .bpi_reset_n_o(bpi_reset_n),
    .bpi_ryby_n_i(bpi_ryby_n)
  );

  axi4_line_mem #(
    .PADDR_W_P(AP_PADDR_W),
    .AXI_DATA_W_P(AP_AXI_DATA_W),
    .AXI_ID_W_P(AP_AXI_SLV_ID_W)
  ) ddr_mem_i (
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_i(ddr_axi)
  );


  always #5 clk = ~clk;

  initial begin
    // jal x0,0: stay in Boot ROM while run-state transitions are observed.
    dut.cluster_i.boot_rom_i.mem[16'h20] = 32'h0000_006f;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    fetch_enable = 1'b1;
    repeat (20) @(posedge clk);

    debug_halt_req = 1'b1;
    @(posedge clk);
    debug_halt_req = 1'b0;

    repeat (300) begin
      @(posedge clk);
      if (debug_halted) begin
        if (debug_running)
          $fatal(1, "debug_running remained asserted while halted");
        if (debug_cause != 3'd1)
          $fatal(1, "external halt debug cause mismatch: %0d", debug_cause);
        halted_pc = debug_pc;
        repeat (5) begin
          @(posedge clk);
          if (!debug_halted || debug_running)
            $fatal(1, "external halt state was not retained");
          if (debug_pc != halted_pc)
            $fatal(1, "debug PC changed while halted: %h -> %h", halted_pc, debug_pc);
        end

        debug_resume_req = 1'b1;
        @(posedge clk);
        debug_resume_req = 1'b0;
        repeat (100) begin
          @(posedge clk);
          if (debug_running && !debug_halted) begin
            $display("PASS: AP SoC external debug halt/resume route");
            $finish;
          end
        end
        $fatal(1, "timeout waiting for external debug resume");
      end
    end
    $fatal(1, "timeout waiting for external debug halt");
  end
endmodule
