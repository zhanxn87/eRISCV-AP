// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// Extended first-stage boot regression.  Normal mode proves the complete BPI
// payload copy, including cache-line crossings and the payload FENCE.I path.
// +bad_image={magic,version,size,load,entry,checksum} instead proves that the
// ROM refuses the image before it can write back or execute the payload.
// +bpi_ready_delay=<cycles> holds RY/BY# low after reset.
module ap_soc_flash_boot_extended_tb;
  import ap_soc_pkg::*;

  localparam logic [AP_PADDR_W-1:0] PAYLOAD_LOAD_ADDR = AP_DDR_BASE + 48'h1000;
  localparam logic [AP_PADDR_W-1:0] PAYLOAD_MARKER_ADDR = AP_DDR_BASE + 48'h2000;
  localparam logic [63:0] PAYLOAD_MARKER = 64'h5041_594c_4f41_4421;
  localparam int unsigned AP_HEADER_BYTES = 64;
  localparam int unsigned PAYLOAD_STAGE_OLD_OFFSET = 44;
  localparam logic [31:0] PAYLOAD_STAGE_OLD_PATCH = 32'h0003_0067;

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
  logic bpi_model_ryby_n;
  logic bpi_ryby_n;
  logic bpi_ready_gate;
  logic bpi_wait_seen;
  logic boot_ddr_write_seen;
  int unsigned bpi_read_cycles;
  int unsigned bpi_ready_delay;
  int unsigned bpi_ready_count;
  string bad_image;
  logic expect_boot_fail;
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
    .BOOT_ROM_INIT_FILE_P("../../../sw/ap_bootrom/build/bootrom.mem")
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
    .SPARSE_P(1'b1)
  ) ddr_mem_i (
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_i(ddr_axi)
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
    .ryby_n_o(bpi_model_ryby_n)
  );

  assign bpi_ryby_n = bpi_model_ryby_n && bpi_ready_gate;

  always #5 clk = ~clk;

  task automatic corrupt_bpi_image;
    begin
      case (bad_image)
        "magic":    bpi_nor_i.preload_word('d0, 16'h0000);
        "version":  bpi_nor_i.preload_word('d4, 16'h0002);
        "size":     bpi_nor_i.preload_word('d8, 16'h0001);
        "load":     bpi_nor_i.preload_word('d13, 16'h0000);
        "entry":    bpi_nor_i.preload_word('d17, 16'h0000);
        "checksum": bpi_nor_i.preload_word(AP_HEADER_BYTES / 2,
                                             bpi_nor_i.mem[AP_HEADER_BYTES / 2] ^ 16'h0001);
        default: $fatal(1, "unsupported +bad_image=%s", bad_image);
      endcase
    end
  endtask

  task automatic check_payload_copy;
    logic [63:0] payload_size;
    logic [511:0] payload_line;
    logic [7:0] ddr_byte;
    logic [7:0] bpi_byte;
    int unsigned byte_index;
    begin
      payload_size = {bpi_nor_i.mem[11], bpi_nor_i.mem[10],
                      bpi_nor_i.mem[9], bpi_nor_i.mem[8]};
      if (payload_size <= 64)
        $fatal(1, "payload did not cross a 64-byte cache line: %0d bytes", payload_size);
      for (byte_index = 0; byte_index < payload_size; byte_index = byte_index + 1) begin
        if ((byte_index & 6'h3f) == 0)
          ddr_mem_i.read_line(PAYLOAD_LOAD_ADDR + (byte_index & ~6'h3f), payload_line);
        ddr_byte = payload_line[(byte_index & 6'h3f) * 8 +: 8];
        if ((byte_index >= PAYLOAD_STAGE_OLD_OFFSET) &&
            (byte_index < (PAYLOAD_STAGE_OLD_OFFSET + 4)))
          bpi_byte = PAYLOAD_STAGE_OLD_PATCH[(byte_index - PAYLOAD_STAGE_OLD_OFFSET) * 8 +: 8];
        else
          bpi_byte = bpi_nor_i.mem[(AP_HEADER_BYTES / 2) + (byte_index >> 1)]
                                      [(byte_index & 1) * 8 +: 8];
        if (ddr_byte !== bpi_byte)
          $fatal(1, "BPI-to-DDR copy mismatch at byte %0d: got %02x expected %02x",
                 byte_index, ddr_byte, bpi_byte);
      end
    end
  endtask

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bpi_ready_gate <= (bpi_ready_delay == 0);
      bpi_ready_count <= '0;
    end else if (!bpi_ready_gate) begin
      if ((bpi_ready_count + 1) >= bpi_ready_delay)
        bpi_ready_gate <= 1'b1;
      else
        bpi_ready_count <= bpi_ready_count + 1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bpi_read_cycles <= '0;
      boot_ddr_write_seen <= 1'b0;
      bpi_wait_seen <= 1'b0;
    end else begin
      if (!bpi_ce_n && !bpi_oe_n && bpi_we_n)
        bpi_read_cycles <= bpi_read_cycles + 1;
      if (!bpi_ready_gate && !bpi_ce_n && !bpi_oe_n)
        bpi_wait_seen <= 1'b1;
      if (ddr_axi.aw_valid && ddr_axi.aw_ready &&
          ddr_axi.aw_addr == PAYLOAD_LOAD_ADDR)
        boot_ddr_write_seen <= 1'b1;
    end
  end

  initial begin
    bpi_ready_delay = 0;
    void'($value$plusargs("bpi_ready_delay=%d", bpi_ready_delay));
    bad_image = "";
    expect_boot_fail = $value$plusargs("bad_image=%s", bad_image);

    // Let the NOR model load the standard image, then inject the requested
    // fault while the complete SoC is still in reset.
    repeat (2) @(posedge clk);
    if (expect_boot_fail)
      corrupt_bpi_image();
    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    fetch_enable = 1'b1;

    repeat (50000) begin
      @(posedge clk);
      ddr_mem_i.read_line(PAYLOAD_MARKER_ADDR, marker_line);
      if (marker_line[63:0] == PAYLOAD_MARKER) begin
        if (expect_boot_fail)
          $fatal(1, "rejected image unexpectedly executed its payload: %s", bad_image);
        if (bpi_read_cycles < 64)
          $fatal(1, "boot did not perform expected BPI reads: %0d", bpi_read_cycles);
        if (!boot_ddr_write_seen)
          $fatal(1, "payload did not reach DDR through the D-Cache writeback path");
        if ((bpi_ready_delay != 0) && !bpi_wait_seen)
          $fatal(1, "BPI RY/BY# delay was not observed on an active NOR read");
        check_payload_copy();
        $display("PASS: AP boot BPI copy/checksum/FENCE.I/cache-line regression");
        $finish;
      end
    end

    if (expect_boot_fail) begin
      if (bpi_read_cycles == 0)
        $fatal(1, "boot rejection did not read the BPI header: %s", bad_image);
      if (boot_ddr_write_seen)
        $fatal(1, "rejected image wrote a payload line to DDR: %s", bad_image);
      $display("PASS: AP boot rejected corrupt BPI image: %s", bad_image);
      $finish;
    end else begin
      $fatal(1, "timeout waiting for boot payload DDR marker");
    end
  end

endmodule
