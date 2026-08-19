// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// Ethernet descriptor-ring regression. Two TX and two RX descriptors live in
// DDR. The test proves descriptor fetch, DMA payload transfers, GMII framing,
// completion writes, IRQ delivery, and producer/consumer head advancement.
module ap_ethernet_dma_tb;
  import ap_soc_pkg::*;

  localparam logic [AP_PADDR_W-1:0] TX0_ADDR = AP_DDR_BASE + 48'h100;
  localparam logic [AP_PADDR_W-1:0] TX1_ADDR = AP_DDR_BASE + 48'h200;
  localparam logic [AP_PADDR_W-1:0] RX0_ADDR = AP_DDR_BASE + 48'h400;
  localparam logic [AP_PADDR_W-1:0] RX1_ADDR = AP_DDR_BASE + 48'h500;
  localparam logic [AP_PADDR_W-1:0] TX_RING_ADDR = AP_DDR_BASE + 48'h800;
  localparam logic [AP_PADDR_W-1:0] RX_RING_ADDR = AP_DDR_BASE + 48'h900;
  localparam int unsigned FRAME_BYTES = 60;
  localparam int unsigned RING_COUNT = 4;
  localparam logic [63:0] DESC_FLAGS = 64'h0000_0000_0007_0000;

  logic clk = 1'b0;
  logic eth_rx_clk = 1'b0;
  logic eth_tx_clk = 1'b0;
  logic rst_n = 1'b0;
  logic eth_rst_n = 1'b0;
  logic apb_psel;
  logic apb_penable;
  logic apb_pwrite;
  logic [AP_PADDR_W-1:0] apb_paddr;
  logic [31:0] apb_pwdata;
  logic [3:0] apb_pstrb;
  logic apb_pready;
  logic [31:0] apb_prdata;
  logic apb_pslverr;
  logic irq;
  logic [7:0] gmii_txd;
  logic gmii_tx_en;
  logic gmii_tx_er;
  logic [7:0] gmii_rxd;
  logic gmii_rx_dv;
  logic gmii_rx_er;
  logic tx_desc_ar_seen;
  logic rx_desc_ar_seen;
  logic tx_payload_ar_seen;
  logic rx_payload_aw_seen;
  logic tx_status_aw_seen;
  logic rx_status_aw_seen;
  logic [511:0] line_data;
  logic [511:0] tx_ring_line;
  logic [511:0] rx_ring_line;
  integer byte_index;
  integer tx_gmii_count;
  integer tx_frame_index;
  logic [31:0] tx_crc;

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) ddr_axi ();

  ap_ethernet_subsystem dut (
    .clk(clk),
    .rst_n(rst_n),
    .apb_psel_i(apb_psel),
    .apb_penable_i(apb_penable),
    .apb_pwrite_i(apb_pwrite),
    .apb_paddr_i(apb_paddr),
    .apb_pwdata_i(apb_pwdata),
    .apb_pstrb_i(apb_pstrb),
    .apb_pready_o(apb_pready),
    .apb_prdata_o(apb_prdata),
    .apb_pslverr_o(apb_pslverr),
    .eth_rx_clk_i(eth_rx_clk),
    .eth_rx_rst_n_i(eth_rst_n),
    .eth_gmii_rxd_i(gmii_rxd),
    .eth_gmii_rx_dv_i(gmii_rx_dv),
    .eth_gmii_rx_er_i(gmii_rx_er),
    .eth_tx_clk_i(eth_tx_clk),
    .eth_tx_rst_n_i(eth_rst_n),
    .eth_gmii_clk_enable_i(1'b1),
    .eth_gmii_txd_o(gmii_txd),
    .eth_gmii_tx_en_o(gmii_tx_en),
    .eth_gmii_tx_er_o(gmii_tx_er),
    .irq_o(irq),
    .mem_axi_o(ddr_axi)
  );

  axi4_line_mem #(
    .PADDR_W_P(AP_PADDR_W),
    .AXI_DATA_W_P(AP_AXI_DATA_W),
    .AXI_ID_W_P(AP_AXI_SLV_ID_W),
    .SPARSE_P(1'b1),
    .MAX_READ_TXNS_P(4),
    .MAX_WRITE_TXNS_P(4)
  ) ddr_mem_i (
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_i(ddr_axi)
  );

  function automatic logic [31:0] crc32_update_byte(
    input logic [31:0] crc_i,
    input logic [7:0] data_i
  );
    logic [31:0] crc;
    integer bit_index;
    begin
      crc = crc_i;
      for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
        if (crc[0] ^ data_i[bit_index])
          crc = (crc >> 1) ^ 32'hedb8_8320;
        else
          crc = crc >> 1;
      end
      crc32_update_byte = crc;
    end
  endfunction

  function automatic logic [7:0] tx_payload_byte(
    input integer frame_i,
    input integer byte_i
  );
    begin
      tx_payload_byte = (frame_i == 0) ? 8'(byte_i + 1) : 8'(8'h80 + byte_i);
    end
  endfunction

  function automatic logic [7:0] rx_payload_byte(
    input integer frame_i,
    input integer byte_i
  );
    begin
      rx_payload_byte = (frame_i == 0) ? 8'(byte_i + 1) : 8'(8'h40 + byte_i);
    end
  endfunction

  always #5 clk = ~clk;
  always #4 eth_tx_clk = ~eth_tx_clk;
  initial begin
    #2;
    forever #4 eth_rx_clk = ~eth_rx_clk;
  end

  always_ff @(negedge eth_tx_clk or negedge eth_rst_n) begin
    if (!eth_rst_n) begin
      tx_gmii_count <= 0;
      tx_frame_index <= 0;
      tx_crc <= 32'hffff_ffff;
    end else if (gmii_tx_en) begin
      if (gmii_tx_er)
        $fatal(1, "GMII TX asserted error");
      if (tx_gmii_count < 7) begin
        if (gmii_txd != 8'h55)
          $fatal(1, "GMII TX preamble mismatch at frame %0d byte %0d",
                 tx_frame_index, tx_gmii_count);
      end else if (tx_gmii_count == 7) begin
        if (gmii_txd != 8'hd5)
          $fatal(1, "GMII TX SFD mismatch");
      end else if (tx_gmii_count < 8 + FRAME_BYTES) begin
        if (gmii_txd != tx_payload_byte(tx_frame_index, tx_gmii_count - 8))
          $fatal(1, "GMII TX payload mismatch at frame %0d byte %0d: %h",
                 tx_frame_index, tx_gmii_count - 8, gmii_txd);
        tx_crc <= crc32_update_byte(tx_crc, gmii_txd);
      end else if (tx_gmii_count == 8 + FRAME_BYTES) begin
        if (gmii_txd != ~tx_crc[7:0])
          $fatal(1, "GMII TX FCS[7:0] mismatch");
      end else if (tx_gmii_count == 9 + FRAME_BYTES) begin
        if (gmii_txd != ~tx_crc[15:8])
          $fatal(1, "GMII TX FCS[15:8] mismatch");
      end else if (tx_gmii_count == 10 + FRAME_BYTES) begin
        if (gmii_txd != ~tx_crc[23:16])
          $fatal(1, "GMII TX FCS[23:16] mismatch");
      end else if (tx_gmii_count == 11 + FRAME_BYTES) begin
        if (gmii_txd != ~tx_crc[31:24])
          $fatal(1, "GMII TX FCS[31:24] mismatch");
      end else begin
        $fatal(1, "GMII TX frame too long");
      end
      if (tx_gmii_count == 0)
        tx_crc <= 32'hffff_ffff;
      tx_gmii_count <= tx_gmii_count + 1;
    end else if (tx_gmii_count != 0) begin
      if (tx_gmii_count != 12 + FRAME_BYTES)
        $fatal(1, "GMII TX frame length mismatch: %0d", tx_gmii_count);
      tx_gmii_count <= 0;
      tx_frame_index <= tx_frame_index + 1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_desc_ar_seen <= 1'b0;
      rx_desc_ar_seen <= 1'b0;
      tx_payload_ar_seen <= 1'b0;
      rx_payload_aw_seen <= 1'b0;
      tx_status_aw_seen <= 1'b0;
      rx_status_aw_seen <= 1'b0;
    end else begin
      if (ddr_axi.ar_valid && ddr_axi.ar_ready) begin
        if ((ddr_axi.ar_addr == TX_RING_ADDR) ||
            (ddr_axi.ar_addr == TX_RING_ADDR + 48'd32))
          tx_desc_ar_seen <= 1'b1;
        if ((ddr_axi.ar_addr == RX_RING_ADDR) ||
            (ddr_axi.ar_addr == RX_RING_ADDR + 48'd32))
          rx_desc_ar_seen <= 1'b1;
        if ((ddr_axi.ar_addr == TX0_ADDR) || (ddr_axi.ar_addr == TX1_ADDR)) begin
          if (ddr_axi.ar_size != 3'd3 || ddr_axi.ar_burst != 2'b01)
            $fatal(1, "TX payload DMA issued invalid AXI read burst");
          tx_payload_ar_seen <= 1'b1;
        end
      end
      if (ddr_axi.aw_valid && ddr_axi.aw_ready) begin
        if ((ddr_axi.aw_addr == RX0_ADDR) || (ddr_axi.aw_addr == RX1_ADDR)) begin
          if (ddr_axi.aw_size != 3'd3 || ddr_axi.aw_burst != 2'b01)
            $fatal(1, "RX payload DMA issued invalid AXI write burst");
          rx_payload_aw_seen <= 1'b1;
        end
        if ((ddr_axi.aw_addr == TX_RING_ADDR + 48'd16) ||
            (ddr_axi.aw_addr == TX_RING_ADDR + 48'd48))
          tx_status_aw_seen <= 1'b1;
        if ((ddr_axi.aw_addr == RX_RING_ADDR + 48'd16) ||
            (ddr_axi.aw_addr == RX_RING_ADDR + 48'd48))
          rx_status_aw_seen <= 1'b1;
      end
    end
  end

  task automatic apb_write(
    input logic [11:0] offset,
    input logic [31:0] data
  );
    begin
      @(negedge clk);
      apb_psel = 1'b1;
      apb_penable = 1'b0;
      apb_pwrite = 1'b1;
      apb_paddr = AP_ETH0_BASE + {{(AP_PADDR_W-12){1'b0}}, offset};
      apb_pwdata = data;
      apb_pstrb = 4'hf;
      @(negedge clk);
      apb_penable = 1'b1;
      @(negedge clk);
      apb_psel = 1'b0;
      apb_penable = 1'b0;
      apb_pwrite = 1'b0;
      apb_paddr = '0;
      apb_pwdata = '0;
      apb_pstrb = '0;
    end
  endtask

  task automatic apb_read(
    input logic [11:0] offset,
    output logic [31:0] data
  );
    begin
      @(negedge clk);
      apb_psel = 1'b1;
      apb_penable = 1'b0;
      apb_pwrite = 1'b0;
      apb_paddr = AP_ETH0_BASE + {{(AP_PADDR_W-12){1'b0}}, offset};
      apb_pstrb = 4'hf;
      @(negedge clk);
      apb_penable = 1'b1;
      @(posedge clk);
      #1;
      data = apb_prdata;
      @(negedge clk);
      apb_psel = 1'b0;
      apb_penable = 1'b0;
      apb_paddr = '0;
      apb_pstrb = '0;
    end
  endtask

  task automatic drive_gmii_byte(input logic [7:0] byte_i);
    begin
      @(negedge eth_rx_clk);
      gmii_rxd = byte_i;
      gmii_rx_dv = 1'b1;
      gmii_rx_er = 1'b0;
    end
  endtask

  task automatic send_rx_frame(input integer frame_i);
    logic [31:0] crc;
    logic [7:0] payload_byte;
    integer frame_byte;
    begin
      crc = 32'hffff_ffff;
      for (frame_byte = 0; frame_byte < 7; frame_byte = frame_byte + 1)
        drive_gmii_byte(8'h55);
      drive_gmii_byte(8'hd5);
      for (frame_byte = 0; frame_byte < FRAME_BYTES; frame_byte = frame_byte + 1) begin
        payload_byte = rx_payload_byte(frame_i, frame_byte);
        drive_gmii_byte(payload_byte);
        crc = crc32_update_byte(crc, payload_byte);
      end
      crc = ~crc;
      drive_gmii_byte(crc[7:0]);
      drive_gmii_byte(crc[15:8]);
      drive_gmii_byte(crc[23:16]);
      drive_gmii_byte(crc[31:24]);
      @(negedge eth_rx_clk);
      gmii_rxd = 8'h00;
      gmii_rx_dv = 1'b0;
      gmii_rx_er = 1'b0;
    end
  endtask

  initial begin : rx_injection
    wait (rst_n && eth_rst_n);
    wait (dut.rx_busy_q);
    repeat (16) @(posedge eth_rx_clk);
    send_rx_frame(0);
    wait (!dut.rx_busy_q);
    wait (dut.rx_busy_q);
    repeat (16) @(posedge eth_rx_clk);
    send_rx_frame(1);
  end

  initial begin
    logic [31:0] irq_status;
    apb_psel = 1'b0;
    apb_penable = 1'b0;
    apb_pwrite = 1'b0;
    apb_paddr = '0;
    apb_pwdata = '0;
    apb_pstrb = '0;
    gmii_rxd = 8'h00;
    gmii_rx_dv = 1'b0;
    gmii_rx_er = 1'b0;

    line_data = '0;
    for (byte_index = 0; byte_index < FRAME_BYTES; byte_index = byte_index + 1)
      line_data[byte_index*8 +: 8] = tx_payload_byte(0, byte_index);
    ddr_mem_i.preload_line(TX0_ADDR, line_data);
    line_data = '0;
    for (byte_index = 0; byte_index < FRAME_BYTES; byte_index = byte_index + 1)
      line_data[byte_index*8 +: 8] = tx_payload_byte(1, byte_index);
    ddr_mem_i.preload_line(TX1_ADDR, line_data);

    tx_ring_line = '0;
    tx_ring_line[0 +: 64] = TX0_ADDR;
    tx_ring_line[64 +: 64] = DESC_FLAGS | FRAME_BYTES;
    tx_ring_line[256 +: 64] = TX1_ADDR;
    tx_ring_line[320 +: 64] = DESC_FLAGS | FRAME_BYTES;
    ddr_mem_i.preload_line(TX_RING_ADDR, tx_ring_line);
    rx_ring_line = '0;
    rx_ring_line[0 +: 64] = RX0_ADDR;
    rx_ring_line[64 +: 64] = DESC_FLAGS | 64'd512;
    rx_ring_line[256 +: 64] = RX1_ADDR;
    rx_ring_line[320 +: 64] = DESC_FLAGS | 64'd512;
    ddr_mem_i.preload_line(RX_RING_ADDR, rx_ring_line);

    repeat (6) @(posedge clk);
    rst_n = 1'b1;
    repeat (6) @(posedge eth_tx_clk);
    eth_rst_n = 1'b1;
    repeat (16) @(posedge clk);

    // Publish the populated DDR rings before enabling/kicking either engine.
    apb_write(12'h010, TX_RING_ADDR[31:0]);
    apb_write(12'h014, {16'b0, TX_RING_ADDR[47:32]});
    apb_write(12'h018, RING_COUNT);
    apb_write(12'h01c, 32'd2);
    apb_write(12'h030, RX_RING_ADDR[31:0]);
    apb_write(12'h034, {16'b0, RX_RING_ADDR[47:32]});
    apb_write(12'h038, RING_COUNT);
    apb_write(12'h03c, 32'd2);
    apb_write(12'h008, 32'h0000_000f);
    apb_write(12'h000, 32'h0000_0003);
    apb_write(12'h024, 32'h1);
    apb_write(12'h044, 32'h1);

    repeat (12000) begin
      @(posedge clk);
      if (irq && (tx_frame_index == 2) && (dut.tx_head == 16'd2) &&
          (dut.rx_head == 16'd2) && tx_desc_ar_seen && rx_desc_ar_seen &&
          tx_payload_ar_seen && rx_payload_aw_seen && tx_status_aw_seen &&
          rx_status_aw_seen) begin
        apb_read(12'h004, irq_status);
        if (irq_status != 4'b0101)
          $fatal(1, "Ethernet ring IRQ status mismatch: %h", irq_status);
        ddr_mem_i.read_line(RX0_ADDR, line_data);
        for (byte_index = 0; byte_index < FRAME_BYTES; byte_index = byte_index + 1)
          if (line_data[byte_index*8 +: 8] != rx_payload_byte(0, byte_index))
            $fatal(1, "RX0 payload mismatch at byte %0d", byte_index);
        ddr_mem_i.read_line(RX1_ADDR, line_data);
        for (byte_index = 0; byte_index < FRAME_BYTES; byte_index = byte_index + 1)
          if (line_data[byte_index*8 +: 8] != rx_payload_byte(1, byte_index))
            $fatal(1, "RX1 payload mismatch at byte %0d", byte_index);
        ddr_mem_i.read_line(TX_RING_ADDR, line_data);
        if (!line_data[128] || !line_data[384] ||
            (line_data[144 +: 16] != FRAME_BYTES) ||
            (line_data[400 +: 16] != FRAME_BYTES))
          $fatal(1, "TX completion status write mismatch");
        ddr_mem_i.read_line(RX_RING_ADDR, line_data);
        if (!line_data[128] || !line_data[384] ||
            (line_data[144 +: 16] != FRAME_BYTES) ||
            (line_data[400 +: 16] != FRAME_BYTES))
          $fatal(1, "RX completion status write mismatch");
        apb_write(12'h000, 32'h0000_0000);
        repeat (4) @(posedge clk);
        apb_write(12'h000, 32'h0000_0004);
        repeat (2) @(posedge clk);
        apb_read(12'h020, irq_status);
        if (irq_status != 0)
          $fatal(1, "TX ring reset did not clear HEAD: %h", irq_status);
        apb_read(12'h040, irq_status);
        if (irq_status != 0)
          $fatal(1, "RX ring reset did not clear HEAD: %h", irq_status);
        /* Linux ifdown first disables RX while a descriptor waits for a frame. */
        apb_write(12'h03c, 32'd1);
        apb_write(12'h000, 32'h0000_0002);
        apb_write(12'h044, 32'h1);
        repeat (64) @(posedge clk);
        apb_read(12'h00c, irq_status);
        if (irq_status[1] != 1'b1)
          $fatal(1, "RX descriptor did not become busy before stop: %h", irq_status);
        apb_write(12'h000, 32'h0000_0000);
        repeat (4) @(posedge clk);
        apb_read(12'h00c, irq_status);
        if (irq_status != 0)
          $fatal(1, "RX stop did not return DMA to idle: %h", irq_status);
        apb_write(12'h000, 32'h0000_0004);
        $display("PASS: AP Ethernet descriptor rings -> AXI64 DMA -> GMII -> DDR completions + stop/reset");
        $finish;
      end
    end
    $fatal(1, "timeout eth-ring: irq=%b tx_head=%0d rx_head=%0d tx_frames=%0d",
           irq, dut.tx_head, dut.rx_head, tx_frame_index);
  end

endmodule
