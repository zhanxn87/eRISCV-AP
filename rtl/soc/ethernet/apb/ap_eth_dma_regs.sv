// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// APB register plane for the Ethernet single-buffer DMA bring-up path.
// Addresses are relative to AP_ETH0_BASE.  DMA addresses are physical 48-bit
// DDR addresses and must be eight-byte aligned. TX length is limited to 1536
// bytes and posted RX capacity to 2048 bytes.
module ap_eth_dma_regs (
  input logic pclk,
  input logic presetn,
  input logic psel_i,
  input logic penable_i,
  input logic pwrite_i,
  input logic [31:0] paddr_i,
  input logic [31:0] pwdata_i,
  input logic [3:0] pstrb_i,
  output logic pready_o,
  output logic [31:0] prdata_o,
  output logic pslverr_o,

  output logic tx_enable_o,
  output logic rx_enable_o,
  output logic [47:0] tx_addr_o,
  output logic [15:0] tx_len_o,
  output logic tx_start_o,
  input logic tx_busy_i,
  input logic tx_done_i,
  input logic tx_error_i,

  output logic [47:0] rx_addr_o,
  output logic [15:0] rx_capacity_o,
  output logic rx_arm_o,
  input logic rx_busy_i,
  input logic rx_done_i,
  input logic [15:0] rx_len_i,
  input logic rx_error_i,

  output logic irq_o
);

  localparam logic [9:0] REG_CTRL       = 10'h000;
  localparam logic [9:0] REG_IRQ_STATUS = 10'h001;
  localparam logic [9:0] REG_IRQ_ENABLE = 10'h002;
  localparam logic [9:0] REG_STATUS     = 10'h003;
  localparam logic [9:0] REG_TX_ADDR_LO = 10'h004;
  localparam logic [9:0] REG_TX_ADDR_HI = 10'h005;
  localparam logic [9:0] REG_TX_LEN     = 10'h006;
  localparam logic [9:0] REG_TX_KICK    = 10'h007;
  localparam logic [9:0] REG_RX_ADDR_LO = 10'h008;
  localparam logic [9:0] REG_RX_ADDR_HI = 10'h009;
  localparam logic [9:0] REG_RX_CAP     = 10'h00a;
  localparam logic [9:0] REG_RX_ARM     = 10'h00b;
  localparam logic [9:0] REG_RX_LEN     = 10'h00c;

  logic [31:0] tx_addr_lo_q;
  logic [15:0] tx_addr_hi_q;
  logic [15:0] tx_len_q;
  logic [31:0] rx_addr_lo_q;
  logic [15:0] rx_addr_hi_q;
  logic [15:0] rx_capacity_q;
  logic [3:0] irq_status_q;
  logic [3:0] irq_enable_q;

  assign pready_o = 1'b1;
  assign pslverr_o = 1'b0;
  assign tx_addr_o = {tx_addr_hi_q, tx_addr_lo_q};
  assign tx_len_o = tx_len_q;
  assign rx_addr_o = {rx_addr_hi_q, rx_addr_lo_q};
  assign rx_capacity_o = rx_capacity_q;
  assign irq_o = |(irq_status_q & irq_enable_q);

  always_comb begin
    prdata_o = '0;
    unique case (paddr_i[11:2])
      REG_CTRL:       prdata_o = {30'b0, rx_enable_o, tx_enable_o};
      REG_IRQ_STATUS: prdata_o = {28'b0, irq_status_q};
      REG_IRQ_ENABLE: prdata_o = {28'b0, irq_enable_q};
      REG_STATUS:     prdata_o = {30'b0, rx_busy_i, tx_busy_i};
      REG_TX_ADDR_LO: prdata_o = tx_addr_lo_q;
      REG_TX_ADDR_HI: prdata_o = {16'b0, tx_addr_hi_q};
      REG_TX_LEN:     prdata_o = {16'b0, tx_len_q};
      REG_RX_ADDR_LO: prdata_o = rx_addr_lo_q;
      REG_RX_ADDR_HI: prdata_o = {16'b0, rx_addr_hi_q};
      REG_RX_CAP:     prdata_o = {16'b0, rx_capacity_q};
      REG_RX_LEN:     prdata_o = {16'b0, rx_len_i};
      default: ;
    endcase
  end

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      tx_enable_o <= 1'b0;
      rx_enable_o <= 1'b0;
      tx_addr_lo_q <= '0;
      tx_addr_hi_q <= '0;
      tx_len_q <= '0;
      rx_addr_lo_q <= '0;
      rx_addr_hi_q <= '0;
      rx_capacity_q <= '0;
      irq_status_q <= '0;
      irq_enable_q <= '0;
      tx_start_o <= 1'b0;
      rx_arm_o <= 1'b0;
    end else begin
      tx_start_o <= 1'b0;
      rx_arm_o <= 1'b0;
      if (tx_done_i)
        irq_status_q[0] <= 1'b1;
      if (tx_error_i)
        irq_status_q[1] <= 1'b1;
      if (rx_done_i)
        irq_status_q[2] <= 1'b1;
      if (rx_error_i)
        irq_status_q[3] <= 1'b1;

      if (psel_i && penable_i && pwrite_i) begin
        unique case (paddr_i[11:2])
          REG_CTRL: begin
            if (pstrb_i[0]) begin
              tx_enable_o <= pwdata_i[0];
              rx_enable_o <= pwdata_i[1];
            end
          end
          REG_IRQ_STATUS: begin
            if (pstrb_i[0])
              irq_status_q <= irq_status_q & ~pwdata_i[3:0];
          end
          REG_IRQ_ENABLE: begin
            if (pstrb_i[0])
              irq_enable_q <= pwdata_i[3:0];
          end
          REG_TX_ADDR_LO: begin
            for (int byte_lane = 0; byte_lane < 4; byte_lane = byte_lane + 1)
              if (pstrb_i[byte_lane])
                tx_addr_lo_q[byte_lane*8 +: 8] <= pwdata_i[byte_lane*8 +: 8];
          end
          REG_TX_ADDR_HI: begin
            if (pstrb_i[0]) tx_addr_hi_q[7:0] <= pwdata_i[7:0];
            if (pstrb_i[1]) tx_addr_hi_q[15:8] <= pwdata_i[15:8];
          end
          REG_TX_LEN: begin
            if (pstrb_i[0]) tx_len_q[7:0] <= pwdata_i[7:0];
            if (pstrb_i[1]) tx_len_q[15:8] <= pwdata_i[15:8];
          end
          REG_TX_KICK: begin
            if (pstrb_i[0] && pwdata_i[0]) begin
              if (tx_enable_o && !tx_busy_i && (tx_len_q != 0))
                tx_start_o <= 1'b1;
              else
                irq_status_q[1] <= 1'b1;
            end
          end
          REG_RX_ADDR_LO: begin
            for (int byte_lane = 0; byte_lane < 4; byte_lane = byte_lane + 1)
              if (pstrb_i[byte_lane])
                rx_addr_lo_q[byte_lane*8 +: 8] <= pwdata_i[byte_lane*8 +: 8];
          end
          REG_RX_ADDR_HI: begin
            if (pstrb_i[0]) rx_addr_hi_q[7:0] <= pwdata_i[7:0];
            if (pstrb_i[1]) rx_addr_hi_q[15:8] <= pwdata_i[15:8];
          end
          REG_RX_CAP: begin
            if (pstrb_i[0]) rx_capacity_q[7:0] <= pwdata_i[7:0];
            if (pstrb_i[1]) rx_capacity_q[15:8] <= pwdata_i[15:8];
          end
          REG_RX_ARM: begin
            if (pstrb_i[0] && pwdata_i[0]) begin
              if (rx_enable_o && !rx_busy_i && (rx_capacity_q != 0))
                rx_arm_o <= 1'b1;
              else
                irq_status_q[3] <= 1'b1;
            end
          end
          default: ;
        endcase
      end
    end
  end

endmodule
