// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// End-to-end Sv39 hart-route test. M-mode Boot ROM code creates a three-level
// page table in DDR, enters S-mode at virtual address 0x4000_0000, then checks
// that independent ITLB and DTLB walks issue six physical PTE reads before
// fetching and loading from the mapped DDR page.
module ap_soc_sv39_route_tb;
  import ap_soc_pkg::*;
  import riscv_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic fetch_enable = 1'b0;
  logic satp_seen;
  logic s_mode_seen;
  logic translated_fetch_seen;
  logic translated_instruction_seen;
  int unsigned ptw_read_count;
  int unsigned ptw_amo_count;
  logic [511:0] s_mode_line;
  logic [63:0] mtime = '0;
  logic [31:0] irq = '0;

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
    .debug_halt_req_i(1'b0),
    .debug_resume_req_i(1'b0),
    .debug_halted_o(),
    .debug_running_o(),
    .debug_pc_o(),
    .debug_cause_o(),
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
    .AXI_ID_W_P(AP_AXI_SLV_ID_W),
    .SPARSE_P(1'b1),
    .MAX_READ_TXNS_P(2),
    .MAX_WRITE_TXNS_P(2),
    .READ_LATENCY_P(1),
    .AR_STALL_CYCLES_P(1),
    .AW_STALL_CYCLES_P(1)
  ) ddr_mem_i (
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_i(ddr_axi)
  );

  // The peripheral complex is not part of this translated DDR-fetch test.

  always #5 clk = ~clk;

  initial begin
    // Reset vector is Boot ROM byte address 0x80, word index 0x20. The code
    // writes root/L1/L0 PTEs at 0x8000_1000/2000/3000, enables Sv39 with
    // root PPN 0x80001, sets MPP=S, and mret's to virtual 0x4000_0000.
    dut.cluster_i.boot_rom_i.mem[16'h20] = 32'h0008_02b7;
    dut.cluster_i.boot_rom_i.mem[16'h21] = 32'h0012_829b;
    dut.cluster_i.boot_rom_i.mem[16'h22] = 32'h00c2_9293;
    dut.cluster_i.boot_rom_i.mem[16'h23] = 32'h2000_1337;
    dut.cluster_i.boot_rom_i.mem[16'h24] = 32'h8013_031b;
    dut.cluster_i.boot_rom_i.mem[16'h25] = 32'h0062_b423;
    dut.cluster_i.boot_rom_i.mem[16'h26] = 32'h0004_02b7;
    dut.cluster_i.boot_rom_i.mem[16'h27] = 32'h0012_829b;
    dut.cluster_i.boot_rom_i.mem[16'h28] = 32'h00d2_9293;
    dut.cluster_i.boot_rom_i.mem[16'h29] = 32'h2000_1337;
    dut.cluster_i.boot_rom_i.mem[16'h2a] = 32'hc013_031b;
    dut.cluster_i.boot_rom_i.mem[16'h2b] = 32'h0062_b023;
    dut.cluster_i.boot_rom_i.mem[16'h2c] = 32'h0008_02b7;
    dut.cluster_i.boot_rom_i.mem[16'h2d] = 32'h0032_829b;
    dut.cluster_i.boot_rom_i.mem[16'h2e] = 32'h00c2_9293;
    dut.cluster_i.boot_rom_i.mem[16'h2f] = 32'h2000_0337;
    dut.cluster_i.boot_rom_i.mem[16'h30] = 32'h00f3_031b;
    dut.cluster_i.boot_rom_i.mem[16'h31] = 32'h0062_b023;
    dut.cluster_i.boot_rom_i.mem[16'h32] = 32'h1200_0073;
    dut.cluster_i.boot_rom_i.mem[16'h33] = 32'hfff0_029b;
    dut.cluster_i.boot_rom_i.mem[16'h34] = 32'h02c2_9293;
    dut.cluster_i.boot_rom_i.mem[16'h35] = 32'h0012_8293;
    dut.cluster_i.boot_rom_i.mem[16'h36] = 32'h0132_9293;
    dut.cluster_i.boot_rom_i.mem[16'h37] = 32'h0012_8293;
    dut.cluster_i.boot_rom_i.mem[16'h38] = 32'h1802_9073;
    dut.cluster_i.boot_rom_i.mem[16'h39] = 32'h1200_0073;
    dut.cluster_i.boot_rom_i.mem[16'h3a] = 32'h0000_12b7;
    dut.cluster_i.boot_rom_i.mem[16'h3b] = 32'h8002_829b;
    dut.cluster_i.boot_rom_i.mem[16'h3c] = 32'h3002_a073;
    dut.cluster_i.boot_rom_i.mem[16'h3d] = 32'h4000_02b7;
    dut.cluster_i.boot_rom_i.mem[16'h3e] = 32'h3412_9073;
    dut.cluster_i.boot_rom_i.mem[16'h3f] = 32'h3020_0073;

    // The mapped S-mode target loads then stores the same virtual page. The
    // leaf starts with A=D=0, so fetch sets A and the DTLB-hit store re-walks
    // to set D through the PTW's D-Cache AMOOR port.
    s_mode_line = '0;
    s_mode_line[31:0] = 32'h4000_02b7;
    s_mode_line[63:32] = 32'h0002_b303;
    s_mode_line[95:64] = 32'h0062_b423;
    s_mode_line[127:96] = 32'h0000_006f;
    // Sparse associative storage initializes after time zero in Verilator.
    #1;
    ddr_mem_i.preload_line(AP_DDR_BASE, s_mode_line);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      satp_seen <= 1'b0;
      s_mode_seen <= 1'b0;
      translated_fetch_seen <= 1'b0;
      translated_instruction_seen <= 1'b0;
      ptw_read_count <= '0;
      ptw_amo_count <= '0;
    end else begin
      if (dut.cluster_i.hart_tile_i.hart_satp[63:60] == 4'd8)
        satp_seen <= 1'b1;
      if (dut.cluster_i.hart_tile_i.hart_privilege == PRIV_S)
        s_mode_seen <= 1'b1;
      if (dut.cluster_i.hart_tile_i.memory_frontend_i.mmu_pte_req_valid &&
          dut.cluster_i.hart_tile_i.memory_frontend_i.mmu_pte_req_ready) begin
        if (dut.cluster_i.hart_tile_i.memory_frontend_i.mmu_pte_atomic_op == ATOMIC_OR)
          ptw_amo_count <= ptw_amo_count + 1'b1;
        else
          ptw_read_count <= ptw_read_count + 1'b1;
      end
      if ((dut.cluster_i.hart_tile_i.hart_privilege == PRIV_S) &&
          dut.cluster_i.hart_tile_i.memory_frontend_i.icache_line_req &&
          (dut.cluster_i.hart_tile_i.memory_frontend_i.icache_line_addr == AP_DDR_BASE))
        translated_fetch_seen <= 1'b1;
      if ((dut.cluster_i.hart_tile_i.hart_privilege == PRIV_S) &&
          dut.cluster_i.hart_tile_i.memory_frontend_i.icache_imem_rvalid &&
          (dut.cluster_i.hart_tile_i.memory_frontend_i.icache_imem_addr == AP_DDR_BASE) &&
          (dut.cluster_i.hart_tile_i.memory_frontend_i.icache_imem_rdata == 32'h4000_02b7))
        translated_instruction_seen <= 1'b1;
    end
  end

  initial begin
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    fetch_enable = 1'b1;
    repeat (1500) begin
      @(posedge clk);
      if (satp_seen && s_mode_seen && (ptw_read_count >= 9) &&
          (ptw_amo_count >= 2) && translated_fetch_seen &&
          translated_instruction_seen) begin
        $display("PASS: AP hart Sv39 ITLB/DTLB/PTW atomic A/D -> translated DDR fetch/load/store");
        $finish;
      end
    end
    $fatal(1, "timeout waiting for Sv39 translated hart route: satp=%b s=%b pte_reads=%0d pte_amo=%0d icache=%b instruction=%b",
           satp_seen, s_mode_seen, ptw_read_count, ptw_amo_count, translated_fetch_seen,
           translated_instruction_seen);
  end
endmodule
