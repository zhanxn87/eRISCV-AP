// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// Complete boot-to-Sv39 regression.  Reset starts in Boot ROM; BPI supplies a
// checksum-protected M-mode payload; the payload creates page tables in DDR
// and enters S-mode.  The S-mode load/store forces independent ITLB/DTLB/PTW
// activity and A/D atomic updates without any DDR backdoor program preload.
module ap_soc_flash_boot_sv39_tb;
  import ap_soc_pkg::*;
  import riscv_pkg::*;

  localparam logic [AP_PADDR_W-1:0] PAYLOAD_CODE_ADDR = AP_DDR_BASE + 48'h1_0000;
  localparam logic [AP_PADDR_W-1:0] PAYLOAD_SMODE_CODE_ADDR = PAYLOAD_CODE_ADDR + 48'h100;
  localparam logic [AP_PADDR_W-1:0] PAYLOAD_MARKER_ADDR = AP_DDR_BASE + 48'h1_1000;
  localparam logic [63:0] PAYLOAD_MARKER = 64'h5356_3339_504f_5354;

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
  logic satp_seen;
  logic s_mode_seen;
  logic translated_fetch_seen;
  logic boot_ddr_write_seen;
  int unsigned bpi_read_cycles;
  int unsigned ptw_read_count;
  int unsigned ptw_amo_count;
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
    .BOOT_ROM_INIT_FILE_P("../../../sw/ap_bootrom/build/sv39/bootrom.mem")
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
    .PADDR_W_P(AP_PADDR_W),
    .AXI_DATA_W_P(AP_AXI_DATA_W),
    .AXI_ID_W_P(AP_AXI_SLV_ID_W),
    .SPARSE_P(1'b1),
    .MAX_READ_TXNS_P(2),
    .MAX_WRITE_TXNS_P(2)
  ) ddr_mem_i (
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_i(ddr_axi)
  );

  ap_bpi_nor_model #(
    .ADDR_W_P(AP_BPI_ADDR_W),
    .INIT_FILE_P("../../../sw/ap_bootrom/build/sv39/boot_payload.bpi.mem")
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
      satp_seen <= 1'b0;
      s_mode_seen <= 1'b0;
      translated_fetch_seen <= 1'b0;
      boot_ddr_write_seen <= 1'b0;
      bpi_read_cycles <= '0;
      ptw_read_count <= '0;
      ptw_amo_count <= '0;
    end else begin
      if (dut.cluster_i.hart_tile_i.hart_satp[63:60] == 4'd8)
        satp_seen <= 1'b1;
      if (dut.cluster_i.hart_tile_i.hart_privilege == PRIV_S)
        s_mode_seen <= 1'b1;
      if (!bpi_ce_n && !bpi_oe_n && bpi_we_n)
        bpi_read_cycles <= bpi_read_cycles + 1;
      if (ddr_axi.aw_valid && ddr_axi.aw_ready &&
          ddr_axi.aw_addr == PAYLOAD_CODE_ADDR)
        boot_ddr_write_seen <= 1'b1;
      if (dut.cluster_i.hart_tile_i.memory_frontend_i.mmu_pte_req_valid &&
          dut.cluster_i.hart_tile_i.memory_frontend_i.mmu_pte_req_ready) begin
        if (dut.cluster_i.hart_tile_i.memory_frontend_i.mmu_pte_atomic_op == ATOMIC_OR)
          ptw_amo_count <= ptw_amo_count + 1;
        else
          ptw_read_count <= ptw_read_count + 1;
      end
      if ((dut.cluster_i.hart_tile_i.hart_privilege == PRIV_S) &&
          dut.cluster_i.hart_tile_i.memory_frontend_i.icache_line_req &&
          (dut.cluster_i.hart_tile_i.memory_frontend_i.icache_line_addr == PAYLOAD_SMODE_CODE_ADDR))
        translated_fetch_seen <= 1'b1;
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
        if (bpi_read_cycles < 64)
          $fatal(1, "boot did not perform expected BPI reads: %0d", bpi_read_cycles);
        if (!boot_ddr_write_seen)
          $fatal(1, "Sv39 boot payload did not reach DDR through D-Cache writeback");
        if (!satp_seen || !s_mode_seen || !translated_fetch_seen ||
            (ptw_read_count < 9) || (ptw_amo_count < 2))
          $fatal(1, "incomplete boot-to-Sv39 route: satp=%b s=%b fetch=%b pte_reads=%0d pte_amo=%0d",
                 satp_seen, s_mode_seen, translated_fetch_seen, ptw_read_count, ptw_amo_count);
        $display("PASS: AP Boot ROM -> BPI -> DDR -> S-mode Sv39 ITLB/DTLB/PTW A/D");
        $finish;
      end
    end
    $fatal(1, "timeout waiting for boot-to-Sv39 payload marker: satp=%b s=%b pte_reads=%0d pte_amo=%0d",
           satp_seen, s_mode_seen, ptw_read_count, ptw_amo_count);
  end

endmodule
