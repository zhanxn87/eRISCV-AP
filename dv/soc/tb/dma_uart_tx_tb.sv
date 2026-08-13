// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

module dma_uart_tx_tb;
  import soc_pkg::*;

  logic clk, rst_n;
  logic cfg_req, cfg_we, cfg_resp, cfg_err;
  logic [31:0] cfg_addr, cfg_wdata, cfg_rdata;
  logic dma_req_valid, dma_req_we, dma_req_ready, dma_resp_valid, dma_resp_err, dma_irq;
  logic [3:0] dma_req_be;
  logic [31:0] dma_req_addr, dma_req_wdata, dma_resp_rdata;
  logic dma_uart_tx_valid, dma_uart_tx_ready;
  logic [7:0] dma_uart_tx_data;
  logic cpu_req_valid, cpu_req_we, cpu_req_ready, cpu_resp_valid, cpu_resp_err;
  logic [3:0] cpu_req_be;
  logic [31:0] cpu_req_addr, cpu_req_wdata, cpu_resp_rdata;
  logic uart_tx, uart_irq, uart_busy;
  logic [31:0] status;
  integer errors, cycles, tx_seen;
  logic saw_backpressure;

  dma_controller dma_i (
    .clk, .rst_n,
    .cfg_req_i(cfg_req), .cfg_we_i(cfg_we), .cfg_addr_i(cfg_addr), .cfg_wdata_i(cfg_wdata),
    .cfg_resp_valid_o(cfg_resp), .cfg_rdata_o(cfg_rdata), .cfg_err_o(cfg_err),
    .dma_req_valid_o(dma_req_valid), .dma_req_we_o(dma_req_we), .dma_req_be_o(dma_req_be),
    .dma_req_addr_o(dma_req_addr), .dma_req_wdata_o(dma_req_wdata),
    .dma_req_ready_i(dma_req_ready), .dma_resp_valid_i(dma_resp_valid),
    .dma_resp_rdata_i(dma_resp_rdata), .dma_resp_err_i(dma_resp_err),
    .uart_tx_valid_o(dma_uart_tx_valid), .uart_tx_data_o(dma_uart_tx_data),
    .uart_tx_ready_i(dma_uart_tx_ready), .irq_o(dma_irq)
  );

  system_sram_fabric system_sram_fabric_i (
    .clk, .rst_n,
    .cpu_req_valid_i(cpu_req_valid), .cpu_req_we_i(cpu_req_we), .cpu_req_be_i(cpu_req_be),
    .cpu_req_addr_i(cpu_req_addr), .cpu_req_wdata_i(cpu_req_wdata), .cpu_req_ready_o(cpu_req_ready),
    .cpu_resp_valid_o(cpu_resp_valid), .cpu_resp_rdata_o(cpu_resp_rdata), .cpu_resp_err_o(cpu_resp_err),
    .dma_req_valid_i(dma_req_valid), .dma_req_we_i(dma_req_we), .dma_req_be_i(dma_req_be),
    .dma_req_addr_i(dma_req_addr), .dma_req_wdata_i(dma_req_wdata), .dma_req_ready_o(dma_req_ready),
    .dma_resp_valid_o(dma_resp_valid), .dma_resp_rdata_o(dma_resp_rdata), .dma_resp_err_o(dma_resp_err)
  );

  uart_apb #(.RESET_BAUD_DIV(32'd1), .TX_FIFO_DEPTH(4), .RX_FIFO_DEPTH(4)) uart_i (
    .pclk(clk), .presetn(rst_n),
    .psel_i(1'b0), .penable_i(1'b0), .pwrite_i(1'b0), .paddr_i('0), .pwdata_i('0), .pstrb_i('0),
    .pready_o(), .prdata_o(), .pslverr_o(),
    .dma_tx_valid_i(dma_uart_tx_valid), .dma_tx_data_i(dma_uart_tx_data),
    .dma_tx_ready_o(dma_uart_tx_ready),
    .uart_rx_i(1'b1), .uart_tx_o(uart_tx), .irq_o(uart_irq), .busy_o(uart_busy)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic check(input logic condition, input string message);
    begin
      if (!condition) begin
        errors = errors + 1;
        $display("DMA UART TX FAIL: %s", message);
      end
    end
  endtask

  task automatic cfg_write(input logic [5:0] offset, input logic [31:0] value);
    begin
      @(negedge clk);
      cfg_req = 1'b1;
      cfg_we = 1'b1;
      cfg_addr = DMA_BASE_ADDR + {{26{1'b0}}, offset};
      cfg_wdata = value;
      while (!cfg_resp) @(negedge clk);
      #1 check(!cfg_err, "configuration write response");
      cfg_req = 1'b0;
      cfg_we = 1'b0;
    end
  endtask

  task automatic cfg_read(input logic [5:0] offset, output logic [31:0] value);
    begin
      @(negedge clk);
      cfg_req = 1'b1;
      cfg_we = 1'b0;
      cfg_addr = DMA_BASE_ADDR + {{26{1'b0}}, offset};
      while (!cfg_resp) @(negedge clk);
      #1 check(!cfg_err, "configuration read response");
      value = cfg_rdata;
      cfg_req = 1'b0;
    end
  endtask

  task automatic wait_irq;
    begin
      cycles = 0;
      while (!dma_irq && cycles < 500) begin
        @(posedge clk);
        cycles = cycles + 1;
      end
      check(dma_irq, "DMA interrupt timeout");
    end
  endtask

  always @(posedge clk) begin
    if (rst_n && uart_i.tx_start) begin
      check(uart_i.tx_data == tx_seen[7:0], "UART byte order");
      tx_seen <= tx_seen + 1;
    end
    if (rst_n && dma_uart_tx_valid && !dma_uart_tx_ready)
      saw_backpressure <= 1'b1;
  end

  initial begin
    rst_n = 1'b0;
    cfg_req = 1'b0;
    cfg_we = 1'b0;
    cfg_addr = '0;
    cfg_wdata = '0;
    cpu_req_valid = 1'b0;
    cpu_req_we = 1'b0;
    cpu_req_be = '0;
    cpu_req_addr = '0;
    cpu_req_wdata = '0;
    errors = 0;
    tx_seen = 0;
    saw_backpressure = 1'b0;
    system_sram_fabric_i.gen_bank[0].system_sram_i.sram_i.mem[0] = 32'h03020100;
    system_sram_fabric_i.gen_bank[1].system_sram_i.sram_i.mem[0] = 32'h07060504;
    system_sram_fabric_i.gen_bank[2].system_sram_i.sram_i.mem[0] = 32'h00000008;
    repeat (2) @(posedge clk);
    rst_n = 1'b1;

    cfg_write(6'h08, SYSTEM_SRAM_BASE_ADDR);
    cfg_write(6'h0c, UART0_BASE);
    cfg_write(6'h10, 32'd9);
    cfg_write(6'h00, 32'h0000_0013);
    wait_irq();
    cfg_read(6'h04, status);
    check(status[2:0] == 3'b010, "UART TX transfer must report DONE only");
    check(saw_backpressure, "UART FIFO full must backpressure DMA");

    cycles = 0;
    while (tx_seen < 9 && cycles < 500) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    check(tx_seen == 9, "all UART bytes must be transmitted");

    cfg_write(6'h04, 32'h0000_0006);
    cfg_write(6'h0c, UART0_BASE + 32'd4);
    cfg_write(6'h10, 32'd1);
    cfg_write(6'h00, 32'h0000_0013);
    wait_irq();
    cfg_read(6'h04, status);
    check(status[2:0] == 3'b100, "non-TXDATA UART destination must be rejected");

    if (errors == 0) begin
      $display("DMA UART TX PASS");
    end else begin
      $display("DMA UART TX FAIL: %0d errors", errors);
      $fatal(1);
    end
    $finish;
  end
endmodule
