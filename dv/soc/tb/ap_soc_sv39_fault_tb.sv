// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// Hart-level Sv39 exception routing. Select with +fault_case=1 (I permission),
// 2 (D permission), or 3 (physical PTE read error plus
// +axi_read_error_addr=000080001000).
module ap_soc_sv39_fault_tb;
  import ap_soc_pkg::*;
  import riscv_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic fetch_enable = 1'b0;
  logic [63:0] mtime = '0;
  logic [31:0] irq = '0;
  int unsigned fault_case;
  logic [11:0] leaf_flags;
  xlen_t expected_cause;
  logic trap_seen;

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
  ) periph_axi ();

  soc dut (
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
    .debug_halt_req_i(1'b0),
    .debug_resume_req_i(1'b0),
    .debug_halted_o(),
    .debug_running_o(),
    .debug_pc_o(),
    .debug_cause_o(),
    .ddr_axi_o(ddr_axi),
    .periph_axi_o(periph_axi)
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

  initial begin
    fault_case = 1;
    void'($value$plusargs("fault_case=%d", fault_case));
    unique case (fault_case)
      1: begin
        leaf_flags = 12'h0c7; // V/R/W/A/D, no X: instruction page fault.
        expected_cause = xlen_t'(12);
      end
      2: begin
        leaf_flags = 12'h0c9; // V/X/A/D, no R: load page fault.
        expected_cause = xlen_t'(13);
      end
      3: begin
        leaf_flags = 12'h0cf; // Valid mapping; AXI PTE read is injected bad.
        expected_cause = xlen_t'(1);
      end
      default: $fatal(1, "fault_case must be 1, 2, or 3");
    endcase

    // Root/L1/L0 setup and M-mode to S-mode transition, matching the route
    // test. leaf_flags is the only policy variation.
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
    dut.cluster_i.boot_rom_i.mem[16'h30] = 32'h0003_031b | (leaf_flags << 20);
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

    // The PTE read-error case must not populate the D-Cache with software
    // page-table stores before the PTW reads the root. Leave the common
    // satp/mstatus/mepc/mret transition intact at 0x32 onward.
    if (fault_case == 3) begin
      for (int word_index = 16'h20; word_index <= 16'h31; word_index++)
        dut.cluster_i.boot_rom_i.mem[word_index] = 32'h0000_0013;
    end

    // Used only by the data-permission case after a successful translated
    // instruction fetch.
    ddr_mem_i.mem[0] = '0;
    ddr_mem_i.mem[0][31:0] = 32'h4000_02b7;
    ddr_mem_i.mem[0][63:32] = 32'h0002_b303;
    ddr_mem_i.mem[0][95:64] = 32'h0000_006f;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      trap_seen <= 1'b0;
    end else if (dut.cluster_i.hart_tile_i.riscv_core_i.ex_stage_i.csr_file_i.mcause_q ==
                 expected_cause) begin
      trap_seen <= 1'b1;
    end
  end

  initial begin
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    fetch_enable = 1'b1;
    repeat (1500) begin
      @(posedge clk);
      if (trap_seen) begin
        $display("PASS: AP hart Sv39 fault_case=%0d mcause=%0d", fault_case, expected_cause);
        $finish;
      end
    end
    $fatal(1, "timeout waiting for Sv39 fault_case=%0d expected mcause=%0d actual=%h",
           fault_case, expected_cause,
           dut.cluster_i.hart_tile_i.riscv_core_i.ex_stage_i.csr_file_i.mcause_q);
  end
endmodule
