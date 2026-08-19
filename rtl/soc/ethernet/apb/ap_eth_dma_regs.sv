// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// APB control plane for the AP Ethernet descriptor-ring DMA engine.
// All ring bases and buffer addresses are physical DDR addresses. Rings are
// power-of-two, contain 2..256 32-byte descriptors, and use HEAD/TAIL indices.
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
  output logic ring_reset_o,
  output logic rx_enable_o,
  output logic [47:0] tx_ring_base_o,
  output logic [15:0] tx_ring_count_o,
  output logic [15:0] tx_tail_o,
  output logic tx_doorbell_o,
  input logic [15:0] tx_head_i,
  input logic tx_busy_i,
  input logic tx_done_i,
  input logic tx_error_i,

  output logic [47:0] rx_ring_base_o,
  output logic [15:0] rx_ring_count_o,
  output logic [15:0] rx_tail_o,
  output logic rx_doorbell_o,
  input logic [15:0] rx_head_i,
  input logic rx_busy_i,
  input logic rx_done_i,
  input logic rx_error_i,

  output logic irq_o
);

  localparam logic [9:0] REG_CTRL        = 10'h000;
  localparam logic [9:0] REG_IRQ_STATUS  = 10'h001;
  localparam logic [9:0] REG_IRQ_ENABLE  = 10'h002;
  localparam logic [9:0] REG_STATUS      = 10'h003;
  localparam logic [9:0] REG_TX_BASE_LO  = 10'h004;
  localparam logic [9:0] REG_TX_BASE_HI  = 10'h005;
  localparam logic [9:0] REG_TX_COUNT    = 10'h006;
  localparam logic [9:0] REG_TX_TAIL     = 10'h007;
  localparam logic [9:0] REG_TX_HEAD     = 10'h008;
  localparam logic [9:0] REG_TX_DOORBELL = 10'h009;
  localparam logic [9:0] REG_RX_BASE_LO  = 10'h00c;
  localparam logic [9:0] REG_RX_BASE_HI  = 10'h00d;
  localparam logic [9:0] REG_RX_COUNT    = 10'h00e;
  localparam logic [9:0] REG_RX_TAIL     = 10'h00f;
  localparam logic [9:0] REG_RX_HEAD     = 10'h010;
  localparam logic [9:0] REG_RX_DOORBELL = 10'h011;
  localparam logic [9:0] REG_CAPS        = 10'h014;
  localparam logic [9:0] REG_MAC_LO      = 10'h015;
  localparam logic [9:0] REG_MAC_HI      = 10'h016;

  localparam logic [47:0] DEFAULT_MAC = 48'h02_00_00_00_00_01;

  logic [31:0] tx_ring_base_lo_q;
  logic [15:0] tx_ring_base_hi_q;
  logic [15:0] tx_ring_count_q;
  logic [15:0] tx_tail_q;
  logic [31:0] rx_ring_base_lo_q;
  logic [15:0] rx_ring_base_hi_q;
  logic [15:0] rx_ring_count_q;
  logic [15:0] rx_tail_q;
  logic [3:0] irq_status_q;
  logic [3:0] irq_enable_q;
  logic [3:0] irq_event;
  logic [3:0] irq_clear;

  assign pready_o = 1'b1;
  assign pslverr_o = 1'b0;
  assign tx_ring_base_o = {tx_ring_base_hi_q, tx_ring_base_lo_q};
  assign tx_ring_count_o = tx_ring_count_q;
  assign tx_tail_o = tx_tail_q;
  assign rx_ring_base_o = {rx_ring_base_hi_q, rx_ring_base_lo_q};
  assign rx_ring_count_o = rx_ring_count_q;
  assign rx_tail_o = rx_tail_q;
  assign irq_o = |(irq_status_q & irq_enable_q);
  assign irq_event = {rx_error_i, rx_done_i, tx_error_i, tx_done_i};
  assign irq_clear = (psel_i && penable_i && pwrite_i &&
                      (paddr_i[11:2] == REG_IRQ_STATUS) && pstrb_i[0]) ?
                     pwdata_i[3:0] : 4'b0;

  always_comb begin
    prdata_o = '0;
    unique case (paddr_i[11:2])
      REG_CTRL:       prdata_o = {30'b0, rx_enable_o, tx_enable_o};
      REG_IRQ_STATUS: prdata_o = {28'b0, irq_status_q};
      REG_IRQ_ENABLE: prdata_o = {28'b0, irq_enable_q};
      REG_STATUS:     prdata_o = {30'b0, rx_busy_i, tx_busy_i};
      REG_TX_BASE_LO: prdata_o = tx_ring_base_lo_q;
      REG_TX_BASE_HI: prdata_o = {16'b0, tx_ring_base_hi_q};
      REG_TX_COUNT:   prdata_o = {16'b0, tx_ring_count_q};
      REG_TX_TAIL:    prdata_o = {16'b0, tx_tail_q};
      REG_TX_HEAD:    prdata_o = {16'b0, tx_head_i};
      REG_RX_BASE_LO: prdata_o = rx_ring_base_lo_q;
      REG_RX_BASE_HI: prdata_o = {16'b0, rx_ring_base_hi_q};
      REG_RX_COUNT:   prdata_o = {16'b0, rx_ring_count_q};
      REG_RX_TAIL:    prdata_o = {16'b0, rx_tail_q};
      REG_RX_HEAD:    prdata_o = {16'b0, rx_head_i};
      REG_CAPS:       prdata_o = 32'h0001_2020; // ring v1, 32-byte desc, 256 max
      REG_MAC_LO:     prdata_o = DEFAULT_MAC[31:0];
      REG_MAC_HI:     prdata_o = {16'b0, DEFAULT_MAC[47:32]};
      default: ;
    endcase
  end

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      tx_enable_o <= 1'b0;
      rx_enable_o <= 1'b0;
      tx_ring_base_lo_q <= '0;
      tx_ring_base_hi_q <= '0;
      tx_ring_count_q <= '0;
      tx_tail_q <= '0;
      rx_ring_base_lo_q <= '0;
      rx_ring_base_hi_q <= '0;
      rx_ring_count_q <= '0;
      rx_tail_q <= '0;
      irq_status_q <= '0;
      irq_enable_q <= '0;
      tx_doorbell_o <= 1'b0;
      rx_doorbell_o <= 1'b0;
      ring_reset_o <= 1'b0;
    end else begin
      tx_doorbell_o <= 1'b0;
      rx_doorbell_o <= 1'b0;
      ring_reset_o <= 1'b0;
      irq_status_q <= (irq_status_q & ~irq_clear) | irq_event;

      if (psel_i && penable_i && pwrite_i) begin
        unique case (paddr_i[11:2])
          REG_CTRL: begin
            if (pstrb_i[0]) begin
              tx_enable_o <= pwdata_i[0];
              rx_enable_o <= pwdata_i[1];
              if (pwdata_i[2])
                ring_reset_o <= 1'b1;
            end
          end
          REG_IRQ_STATUS: ;
          REG_IRQ_ENABLE: begin
            if (pstrb_i[0])
              irq_enable_q <= pwdata_i[3:0];
          end
          REG_TX_BASE_LO: begin
            for (int byte_lane = 0; byte_lane < 4; byte_lane = byte_lane + 1)
              if (pstrb_i[byte_lane])
                tx_ring_base_lo_q[byte_lane*8 +: 8] <= pwdata_i[byte_lane*8 +: 8];
          end
          REG_TX_BASE_HI: begin
            if (pstrb_i[0]) tx_ring_base_hi_q[7:0] <= pwdata_i[7:0];
            if (pstrb_i[1]) tx_ring_base_hi_q[15:8] <= pwdata_i[15:8];
          end
          REG_TX_COUNT: begin
            if (pstrb_i[0]) tx_ring_count_q[7:0] <= pwdata_i[7:0];
            if (pstrb_i[1]) tx_ring_count_q[15:8] <= pwdata_i[15:8];
          end
          REG_TX_TAIL: begin
            if (pstrb_i[0]) tx_tail_q[7:0] <= pwdata_i[7:0];
            if (pstrb_i[1]) tx_tail_q[15:8] <= pwdata_i[15:8];
          end
          REG_TX_DOORBELL: begin
            if (pstrb_i[0] && pwdata_i[0])
              tx_doorbell_o <= 1'b1;
          end
          REG_RX_BASE_LO: begin
            for (int byte_lane = 0; byte_lane < 4; byte_lane = byte_lane + 1)
              if (pstrb_i[byte_lane])
                rx_ring_base_lo_q[byte_lane*8 +: 8] <= pwdata_i[byte_lane*8 +: 8];
          end
          REG_RX_BASE_HI: begin
            if (pstrb_i[0]) rx_ring_base_hi_q[7:0] <= pwdata_i[7:0];
            if (pstrb_i[1]) rx_ring_base_hi_q[15:8] <= pwdata_i[15:8];
          end
          REG_RX_COUNT: begin
            if (pstrb_i[0]) rx_ring_count_q[7:0] <= pwdata_i[7:0];
            if (pstrb_i[1]) rx_ring_count_q[15:8] <= pwdata_i[15:8];
          end
          REG_RX_TAIL: begin
            if (pstrb_i[0]) rx_tail_q[7:0] <= pwdata_i[7:0];
            if (pstrb_i[1]) rx_tail_q[15:8] <= pwdata_i[15:8];
          end
          REG_RX_DOORBELL: begin
            if (pstrb_i[0] && pwdata_i[0])
              rx_doorbell_o <= 1'b1;
          end
          default: ;
        endcase
      end
    end
  end

endmodule
