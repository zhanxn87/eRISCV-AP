// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// Direct AP hart-tile boundary smoke. A shared Boot ROM transfers fetch to
// DDR, proving that the tile's exported I-Cache manager emits one 64-byte AXI
// line fill without instantiating ap_cluster or ap_soc.
module ap_hart_tile_smoke_tb;
  import ap_soc_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic fetch_enable = 1'b0;
  logic icache_ddr_read_seen;
  logic [63:0] mtime = '0;
  logic [31:0] irq = '0;

  logic boot_imem_req;
  logic [AP_PADDR_W-1:0] boot_imem_addr;
  logic boot_imem_ready;
  logic boot_imem_rvalid;
  logic [31:0] boot_imem_rdata;

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W), .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W), .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) mem_axi [1:0] ();
  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W), .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W), .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) periph_axi ();

  ap_hart_tile dut (
    .clk(clk),
    .rst_n(rst_n),
    .fetch_enable_i(fetch_enable),
    .mtime_i(mtime),
    .irq_i(irq),
    .debug_halt_req_i(1'b0),
    .debug_resume_req_i(1'b0),
    .debug_halted_o(),
    .debug_running_o(),
    .debug_pc_o(),
    .debug_cause_o(),
    .boot_imem_req_o(boot_imem_req),
    .boot_imem_addr_o(boot_imem_addr),
    .boot_imem_ready_i(boot_imem_ready),
    .boot_imem_rvalid_i(boot_imem_rvalid),
    .boot_imem_rdata_i(boot_imem_rdata),
    .mem_axi_o(mem_axi),
    .periph_axi_o(periph_axi)
  );

  ap_boot_rom #(
    .INIT_FILE_P("../../soc/tb/ap_soc_ddr_boot.mem")
  ) boot_rom_i (
    .clk(clk),
    .rst_n(rst_n),
    .req_i(boot_imem_req),
    .addr_i(boot_imem_addr),
    .ready_o(boot_imem_ready),
    .rvalid_o(boot_imem_rvalid),
    .rdata_o(boot_imem_rdata)
  );

  axi4_line_mem #(
    .PADDR_W_P(AP_PADDR_W),
    .AXI_DATA_W_P(AP_AXI_DATA_W),
    .AXI_ID_W_P(AP_AXI_SLV_ID_W),
    .SPARSE_P(1'b1)
  ) icache_ddr_i (
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_i(mem_axi[0])
  );

  axi4_line_mem #(
    .PADDR_W_P(AP_PADDR_W),
    .AXI_DATA_W_P(AP_AXI_DATA_W),
    .AXI_ID_W_P(AP_AXI_SLV_ID_W),
    .SPARSE_P(1'b1)
  ) dcache_ddr_i (
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_i(mem_axi[1])
  );

  // No MMIO instruction is executed by this smoke. Keep the external manager
  // boundary complete and quiescent.
  assign periph_axi.aw_ready = 1'b0;
  assign periph_axi.w_ready = 1'b0;
  assign periph_axi.b_id = '0;
  assign periph_axi.b_resp = 2'b00;
  assign periph_axi.b_user = '0;
  assign periph_axi.b_valid = 1'b0;
  assign periph_axi.ar_ready = 1'b0;
  assign periph_axi.r_id = '0;
  assign periph_axi.r_data = '0;
  assign periph_axi.r_resp = 2'b00;
  assign periph_axi.r_last = 1'b0;
  assign periph_axi.r_user = '0;
  assign periph_axi.r_valid = 1'b0;

  always #5 clk = ~clk;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      icache_ddr_read_seen <= 1'b0;
    end else if (mem_axi[0].ar_valid && mem_axi[0].ar_ready) begin
      if (mem_axi[0].ar_addr != AP_DDR_BASE)
        $fatal(1, "unexpected I-Cache DDR read address: %h", mem_axi[0].ar_addr);
      if (mem_axi[0].ar_len != 8'd7 || mem_axi[0].ar_size != 3'd3 ||
          mem_axi[0].ar_burst != 2'b01)
        $fatal(1, "I-Cache fill is not an 8-beat 64-bit INCR burst");
      icache_ddr_read_seen <= 1'b1;
    end
  end

  initial begin
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    fetch_enable = 1'b1;
    repeat (300) begin
      @(posedge clk);
      if (icache_ddr_read_seen) begin
        $display("AP HART TILE PASS: Boot ROM -> I-Cache -> DDR AXI");
        $finish;
      end
    end
    $fatal(1, "timeout waiting for hart-tile I-Cache DDR line read");
  end
endmodule
