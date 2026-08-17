// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// Ethernet DMA directed regression.  A 60-byte DDR packet is read by TX DMA
// and emitted through GMII; an independently generated CRC-valid GMII frame is
// received, CDC-crossed, and written into a posted DDR RX buffer.
module ap_ethernet_dma_tb;
  import ap_soc_pkg::*;

  localparam logic [AP_PADDR_W-1:0] TX_ADDR = AP_DDR_BASE + 48'h100;
  localparam logic [AP_PADDR_W-1:0] RX_ADDR = AP_DDR_BASE + 48'h400;
  localparam int unsigned FRAME_BYTES = 60;

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
  logic tx_ar_seen;
  logic rx_aw_seen;
  logic [511:0] line_data;
  integer byte_index;
  integer mac_rx_count;
  logic mac_rx_last_seen;
  logic mac_rx_user_seen;
  integer tx_gmii_count;
  logic tx_gmii_done;
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
    .MAX_READ_TXNS_P(2),
    .MAX_WRITE_TXNS_P(2)
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

  always #5 clk = ~clk;
  always #4 eth_tx_clk = ~eth_tx_clk;
  initial begin
    #2;
    forever #4 eth_rx_clk = ~eth_rx_clk;
  end

  always_ff @(negedge eth_tx_clk or negedge eth_rst_n) begin
    if (!eth_rst_n) begin
      tx_gmii_count <= 0;
      tx_gmii_done <= 1'b0;
      tx_crc <= 32'hffff_ffff;
    end else if (gmii_tx_en) begin
      if (gmii_tx_er)
        $fatal(1, "GMII TX asserted error");
      if (tx_gmii_count < 7) begin
        if (gmii_txd != 8'h55)
          $fatal(1, "GMII TX preamble mismatch at byte %0d: %h",
                 tx_gmii_count, gmii_txd);
      end else if (tx_gmii_count == 7) begin
        if (gmii_txd != 8'hd5)
          $fatal(1, "GMII TX SFD mismatch: %h", gmii_txd);
      end else if (tx_gmii_count < 8 + FRAME_BYTES) begin
        if (gmii_txd != 8'(tx_gmii_count - 7))
          $fatal(1, "GMII TX payload mismatch at byte %0d: %h",
                 tx_gmii_count - 8, gmii_txd);
        tx_crc <= crc32_update_byte(tx_crc, gmii_txd);
      end else if (tx_gmii_count == 8 + FRAME_BYTES) begin
        if (gmii_txd != ~tx_crc[7:0])
          $fatal(1, "GMII TX FCS[7:0] mismatch: %h", gmii_txd);
      end else if (tx_gmii_count == 9 + FRAME_BYTES) begin
        if (gmii_txd != ~tx_crc[15:8])
          $fatal(1, "GMII TX FCS[15:8] mismatch: %h", gmii_txd);
      end else if (tx_gmii_count == 10 + FRAME_BYTES) begin
        if (gmii_txd != ~tx_crc[23:16])
          $fatal(1, "GMII TX FCS[23:16] mismatch: %h", gmii_txd);
      end else if (tx_gmii_count == 11 + FRAME_BYTES) begin
        if (gmii_txd != ~tx_crc[31:24])
          $fatal(1, "GMII TX FCS[31:24] mismatch: %h", gmii_txd);
      end else begin
        $fatal(1, "GMII TX frame too long: byte %0d", tx_gmii_count);
      end
      if (tx_gmii_count == 0)
        tx_crc <= 32'hffff_ffff;
      tx_gmii_count <= tx_gmii_count + 1;
    end else if (tx_gmii_count != 0) begin
      if (tx_gmii_count != 12 + FRAME_BYTES)
        $fatal(1, "GMII TX frame length mismatch: %0d", tx_gmii_count);
      tx_gmii_done <= 1'b1;
      tx_gmii_count <= 0;
    end
  end

  always_ff @(posedge eth_rx_clk or negedge eth_rst_n) begin
    if (!eth_rst_n) begin
      mac_rx_count <= 0;
      mac_rx_last_seen <= 1'b0;
      mac_rx_user_seen <= 1'b0;
    end else if (dut.mac_rx_valid) begin
      mac_rx_count <= mac_rx_count + 1;
      if (dut.mac_rx_last) begin
        mac_rx_last_seen <= 1'b1;
        mac_rx_user_seen <= dut.mac_rx_user;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_ar_seen <= 1'b0;
      rx_aw_seen <= 1'b0;
    end else begin
      if (ddr_axi.ar_valid && ddr_axi.ar_ready && ddr_axi.ar_addr == TX_ADDR) begin
        if (ddr_axi.ar_size != 3'd3 || ddr_axi.ar_burst != 2'b01)
          $fatal(1, "TX DMA issued an invalid AXI read burst");
        tx_ar_seen <= 1'b1;
      end
      if (ddr_axi.aw_valid && ddr_axi.aw_ready && ddr_axi.aw_addr == RX_ADDR) begin
        if (ddr_axi.aw_size != 3'd3 || ddr_axi.aw_burst != 2'b01)
          $fatal(1, "RX DMA issued an invalid AXI write burst");
        rx_aw_seen <= 1'b1;
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

  task automatic send_rx_frame;
    logic [31:0] crc;
    logic [7:0] payload_byte;
    integer frame_byte;
    integer crc_bit;
    begin
      crc = 32'hffff_ffff;
      for (frame_byte = 0; frame_byte < 7; frame_byte = frame_byte + 1)
        drive_gmii_byte(8'h55);
      drive_gmii_byte(8'hd5);
      for (frame_byte = 0; frame_byte < FRAME_BYTES; frame_byte = frame_byte + 1) begin
        payload_byte = 8'(frame_byte + 1);
        drive_gmii_byte(payload_byte);
        for (crc_bit = 0; crc_bit < 8; crc_bit = crc_bit + 1) begin
          if (crc[0] ^ payload_byte[crc_bit])
            crc = (crc >> 1) ^ 32'hedb8_8320;
          else
            crc = crc >> 1;
        end
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
    send_rx_frame();
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
      line_data[byte_index*8 +: 8] = 8'(byte_index + 1);
    ddr_mem_i.preload_line(TX_ADDR, line_data);

    repeat (6) @(posedge clk);
    rst_n = 1'b1;
    repeat (6) @(posedge eth_tx_clk);
    eth_rst_n = 1'b1;
    repeat (16) @(posedge clk);

    // CTRL, IRQ_ENABLE, RX buffer, then TX buffer and kick.
    apb_write(12'h000, 32'h0000_0003);
    apb_write(12'h008, 32'h0000_0005);
    apb_write(12'h020, RX_ADDR[31:0]);
    apb_write(12'h024, {16'b0, RX_ADDR[47:32]});
    apb_write(12'h028, 32'd512);
    apb_write(12'h02c, 32'h1);
    apb_write(12'h010, TX_ADDR[31:0]);
    apb_write(12'h014, {16'b0, TX_ADDR[47:32]});
    apb_write(12'h018, FRAME_BYTES);
    apb_write(12'h01c, 32'h1);

    repeat (3000) begin
      @(posedge clk);
      if (irq && tx_ar_seen && tx_gmii_done && rx_aw_seen && dut.regs_i.irq_status_q[2]) begin
        apb_read(12'h004, irq_status);
        if (irq_status[2:0] != 3'b101 || irq_status[3])
          $fatal(1, "Ethernet DMA status mismatch: %h", irq_status);
        ddr_mem_i.read_line(RX_ADDR, line_data);
        for (byte_index = 0; byte_index < FRAME_BYTES; byte_index = byte_index + 1)
          if (line_data[byte_index*8 +: 8] != 8'(byte_index + 1))
            $fatal(1, "RX payload mismatch at byte %0d: %h", byte_index,
                   line_data[byte_index*8 +: 8]);
        $display("PASS: AP Ethernet APB -> 64-bit AXI DMA -> GMII TX and CRC-valid RX -> DDR");
        $finish;
      end
    end
    $fatal(1, "timeout eth: irq=%b ar=%b aw=%b tx_busy=%b tx_desc=%b tx_ready=%b tx_status=%b rx_busy=%b rx_ready=%b rx_desc=%b rx_issued=%b rx_status=%b irq_status=%b rx_armed=%b rx_capture=%b rx_drop=%b mac_bad_fcs=%b mac_count=%0d mac_last=%b mac_user=%b wr_count=%0d", irq, tx_ar_seen, rx_aw_seen, dut.tx_busy_q, dut.tx_desc_valid_q, dut.tx_desc_ready, dut.dma_read_status_valid, dut.rx_busy_q, dut.rx_frame_ready, dut.rx_desc_valid_q, dut.rx_desc_issued_q, dut.dma_write_status_valid, dut.regs_i.irq_status_q, dut.rx_frame_buffer_i.armed_q, dut.rx_frame_buffer_i.capture_q, dut.rx_frame_buffer_i.drop_q, dut.mac_i.axis_gmii_rx_inst.error_bad_fcs, mac_rx_count, mac_rx_last_seen, mac_rx_user_seen, dut.rx_frame_buffer_i.wr_count_q);
  end

endmodule
