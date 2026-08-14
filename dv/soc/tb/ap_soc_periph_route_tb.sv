// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// AP peripheral routing smoke test. A tiny Boot ROM program loads from
// AP_APB_BASE; the test observes the resulting uncached 64-bit single-beat
// read on axi_periph and rejects any accidental DDR cache fill.
module ap_soc_periph_route_tb;
  import ap_soc_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic fetch_enable = 1'b0;
  logic periph_read_seen;
  logic [63:0] mtime = '0;
  logic [31:0] irq = '0;

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W), .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W), .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) ddr_axi ();
  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W), .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W), .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) periph_axi ();

  soc #(
    .BOOT_ROM_INIT_FILE_P("../tb/ap_soc_periph_boot.mem")
  ) dut (
    .clk, .rst_n, .fetch_enable_i(fetch_enable), .mtime_i(mtime), .irq_i(irq),
    .ddr_axi_o(ddr_axi), .periph_axi_o(periph_axi)
  );

  axi4_line_mem #(
    .PADDR_W_P(AP_PADDR_W), .AXI_DATA_W_P(AP_AXI_DATA_W),
    .AXI_ID_W_P(AP_AXI_SLV_ID_W)
  ) ddr_mem_i (
    .clk, .rst_n,
    .s_axi_awid_i(ddr_axi.aw_id), .s_axi_awaddr_i(ddr_axi.aw_addr),
    .s_axi_awlen_i(ddr_axi.aw_len), .s_axi_awsize_i(ddr_axi.aw_size),
    .s_axi_awburst_i(ddr_axi.aw_burst), .s_axi_awcache_i(ddr_axi.aw_cache),
    .s_axi_awvalid_i(ddr_axi.aw_valid), .s_axi_awready_o(ddr_axi.aw_ready),
    .s_axi_wdata_i(ddr_axi.w_data), .s_axi_wstrb_i(ddr_axi.w_strb),
    .s_axi_wlast_i(ddr_axi.w_last), .s_axi_wvalid_i(ddr_axi.w_valid),
    .s_axi_wready_o(ddr_axi.w_ready), .s_axi_bid_o(ddr_axi.b_id),
    .s_axi_bresp_o(ddr_axi.b_resp), .s_axi_bvalid_o(ddr_axi.b_valid),
    .s_axi_bready_i(ddr_axi.b_ready), .s_axi_arid_i(ddr_axi.ar_id),
    .s_axi_araddr_i(ddr_axi.ar_addr), .s_axi_arlen_i(ddr_axi.ar_len),
    .s_axi_arsize_i(ddr_axi.ar_size), .s_axi_arburst_i(ddr_axi.ar_burst),
    .s_axi_arcache_i(ddr_axi.ar_cache), .s_axi_arvalid_i(ddr_axi.ar_valid),
    .s_axi_arready_o(ddr_axi.ar_ready), .s_axi_rid_o(ddr_axi.r_id),
    .s_axi_rdata_o(ddr_axi.r_data), .s_axi_rresp_o(ddr_axi.r_resp),
    .s_axi_rlast_o(ddr_axi.r_last), .s_axi_rvalid_o(ddr_axi.r_valid),
    .s_axi_rready_i(ddr_axi.r_ready)
  );

  // Peripheral complex is not implemented yet.  Keep its response channels
  // quiescent so this top-level topology test has a complete AXI boundary.
  assign periph_axi.aw_ready = 1'b0;
  assign periph_axi.w_ready = 1'b0;
  assign periph_axi.b_id = '0;
  assign periph_axi.b_resp = 2'b00;
  assign periph_axi.b_user = '0;
  assign periph_axi.b_valid = 1'b0;
  assign periph_axi.ar_ready = 1'b1;
  assign periph_axi.r_id = '0;
  assign periph_axi.r_data = '0;
  assign periph_axi.r_resp = 2'b00;
  assign periph_axi.r_last = 1'b0;
  assign periph_axi.r_user = '0;
  assign periph_axi.r_valid = 1'b0;

  always #5 clk = ~clk;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      periph_read_seen <= 1'b0;
    end else begin
      if (ddr_axi.ar_valid && ddr_axi.ar_ready)
        $fatal(1, "uncached APB load incorrectly issued a DDR read");
      if (periph_axi.ar_valid && periph_axi.ar_ready) begin
        if (periph_axi.ar_addr != AP_APB_BASE)
          $fatal(1, "unexpected peripheral read address: %h", periph_axi.ar_addr);
        if (periph_axi.ar_len != 8'd0 || periph_axi.ar_size != 3'd3 ||
            periph_axi.ar_burst != 2'b01 || periph_axi.ar_cache != 4'b0000)
          $fatal(1, "peripheral read is not an uncached 64-bit single beat");
        periph_read_seen <= 1'b1;
      end
    end
  end

  initial begin
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    fetch_enable = 1'b1;
    repeat (300) begin
      @(posedge clk);
      if (periph_read_seen) begin
        $display("PASS: AP SoC Boot ROM -> uncached axi_periph routing");
        $finish;
      end
    end
    $fatal(1, "timeout waiting for uncached peripheral read");
  end
endmodule
