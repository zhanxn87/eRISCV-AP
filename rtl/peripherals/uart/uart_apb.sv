// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

module uart_apb #(
  parameter logic [31:0] RESET_BAUD_DIV = 32'd8,
  parameter int unsigned TX_FIFO_DEPTH  = 32,
  parameter int unsigned RX_FIFO_DEPTH  = 64
) (
  input  logic        pclk,
  input  logic        presetn,
  input  logic        psel_i,
  input  logic        penable_i,
  input  logic        pwrite_i,
  input  logic [31:0] paddr_i,
  input  logic [31:0] pwdata_i,
  input  logic [3:0]  pstrb_i,
  output logic        pready_o,
  output logic [31:0] prdata_o,
  output logic        pslverr_o,

  input  logic        dma_tx_valid_i,
  input  logic [7:0]  dma_tx_data_i,
  output logic        dma_tx_ready_o,

  input  logic        uart_rx_i,
  output logic        uart_tx_o,
  output logic        irq_o,
  output logic        busy_o
);

  localparam logic [7:0] REG_TXDATA       = 8'h00;
  localparam logic [7:0] REG_RXDATA       = 8'h04;
  localparam logic [7:0] REG_STATUS       = 8'h08;
  localparam logic [7:0] REG_BAUDDIV      = 8'h0c;
  localparam logic [7:0] REG_CTRL         = 8'h10;
  localparam logic [7:0] REG_TX_WATERMARK = 8'h14;
  localparam logic [7:0] REG_RX_WATERMARK = 8'h18;
  localparam logic [7:0] REG_IRQ_STATUS   = 8'h1c;

  localparam int unsigned TX_FIFO_ADDR_WIDTH  = (TX_FIFO_DEPTH > 1) ? $clog2(TX_FIFO_DEPTH) : 1;
  localparam int unsigned TX_FIFO_COUNT_WIDTH = (TX_FIFO_DEPTH > 1) ? $clog2(TX_FIFO_DEPTH + 1) : 1;
  localparam int unsigned RX_FIFO_ADDR_WIDTH  = (RX_FIFO_DEPTH > 1) ? $clog2(RX_FIFO_DEPTH) : 1;
  localparam int unsigned RX_FIFO_COUNT_WIDTH = (RX_FIFO_DEPTH > 1) ? $clog2(RX_FIFO_DEPTH + 1) : 1;
  localparam logic [TX_FIFO_ADDR_WIDTH-1:0] TX_FIFO_LAST_ADDR = TX_FIFO_ADDR_WIDTH'(TX_FIFO_DEPTH - 1);
  localparam logic [TX_FIFO_COUNT_WIDTH-1:0] TX_FIFO_DEPTH_COUNT = TX_FIFO_COUNT_WIDTH'(TX_FIFO_DEPTH);
  localparam logic [RX_FIFO_ADDR_WIDTH-1:0] RX_FIFO_LAST_ADDR = RX_FIFO_ADDR_WIDTH'(RX_FIFO_DEPTH - 1);
  localparam logic [RX_FIFO_COUNT_WIDTH-1:0] RX_FIFO_DEPTH_COUNT = RX_FIFO_COUNT_WIDTH'(RX_FIFO_DEPTH);
  localparam logic [TX_FIFO_COUNT_WIDTH-1:0] DEFAULT_TX_WATERMARK =
      TX_FIFO_COUNT_WIDTH'((TX_FIFO_DEPTH > 4) ? (TX_FIFO_DEPTH / 4) : 0);
  localparam logic [RX_FIFO_COUNT_WIDTH-1:0] DEFAULT_RX_WATERMARK =
      RX_FIFO_COUNT_WIDTH'(1);

  logic        apb_access;
  logic [7:0]  reg_offset;
  logic [31:0] baud_div_q;
  logic [31:0] ctrl_q;
  logic [31:0] irq_status_value;
  logic        baud_tick;
  logic        tx_engine_ready;
  logic        tx_engine_busy;
  logic        tx_start;
  logic [7:0]  tx_data;
  logic        rx_byte_valid;
  logic [7:0]  rx_byte;
  logic        rx_overrun_q;
  logic [31:0] status_value;

  logic [7:0] tx_fifo_q [0:TX_FIFO_DEPTH-1];
  logic [TX_FIFO_ADDR_WIDTH-1:0] tx_rd_ptr_q;
  logic [TX_FIFO_ADDR_WIDTH-1:0] tx_wr_ptr_q;
  logic [TX_FIFO_COUNT_WIDTH-1:0] tx_count_q;
  logic [TX_FIFO_COUNT_WIDTH-1:0] tx_watermark_q;
  logic        tx_fifo_empty;
  logic        tx_fifo_full;
  logic        tx_fifo_ready;
  logic        tx_fifo_push;
  logic        tx_apb_write;
  logic        tx_dma_push;
  logic        tx_direct_start;
  logic        tx_fifo_pop;
  logic        tx_watermark_pending;

  logic [7:0] rx_fifo_q [0:RX_FIFO_DEPTH-1];
  logic [RX_FIFO_ADDR_WIDTH-1:0] rx_rd_ptr_q;
  logic [RX_FIFO_ADDR_WIDTH-1:0] rx_wr_ptr_q;
  logic [RX_FIFO_COUNT_WIDTH-1:0] rx_count_q;
  logic [RX_FIFO_COUNT_WIDTH-1:0] rx_watermark_q;
  logic        rx_fifo_empty;
  logic        rx_fifo_full;
  logic        rx_fifo_push;
  logic        rx_fifo_pop;
  logic        rx_watermark_pending;
  logic        irq_status_clear;

  function automatic logic [TX_FIFO_COUNT_WIDTH-1:0] clamp_tx_watermark(
    input logic [31:0] value
  );
    if (value >= TX_FIFO_DEPTH) begin
      clamp_tx_watermark = TX_FIFO_DEPTH_COUNT;
    end else begin
      clamp_tx_watermark = TX_FIFO_COUNT_WIDTH'(value);
    end
  endfunction

  function automatic logic [RX_FIFO_COUNT_WIDTH-1:0] clamp_rx_watermark(
    input logic [31:0] value
  );
    if (value >= RX_FIFO_DEPTH) begin
      clamp_rx_watermark = RX_FIFO_DEPTH_COUNT;
    end else begin
      clamp_rx_watermark = RX_FIFO_COUNT_WIDTH'(value);
    end
  endfunction

  initial begin
    if ((TX_FIFO_DEPTH == 0) || (RX_FIFO_DEPTH == 0)) begin
      $error("UART FIFO depths must be greater than zero");
    end
  end

  assign apb_access = psel_i & penable_i;
  assign reg_offset = paddr_i[7:0];
  assign pready_o   = 1'b1;
  assign pslverr_o  = apb_access &&
                      (reg_offset != REG_TXDATA) &&
                      (reg_offset != REG_RXDATA) &&
                      (reg_offset != REG_STATUS) &&
                      (reg_offset != REG_BAUDDIV) &&
                      (reg_offset != REG_CTRL) &&
                      (reg_offset != REG_TX_WATERMARK) &&
                      (reg_offset != REG_RX_WATERMARK) &&
                      (reg_offset != REG_IRQ_STATUS);

  assign tx_fifo_empty = (tx_count_q == '0);
  assign tx_fifo_full  = (tx_count_q == TX_FIFO_DEPTH_COUNT);
  assign rx_fifo_empty = (rx_count_q == '0);
  assign rx_fifo_full  = (rx_count_q == RX_FIFO_DEPTH_COUNT);

  // A dequeue in this cycle frees a slot for one write. APB owns a collision
  // with the DMA endpoint; the DMA valid/ready transfer remains pending.
  assign tx_fifo_pop   = tx_engine_ready && !tx_fifo_empty;
  assign tx_fifo_ready = ctrl_q[0] && (!tx_fifo_full || tx_fifo_pop);
  assign tx_apb_write = apb_access && pwrite_i && !pslverr_o &&
                        (reg_offset == REG_TXDATA) && pstrb_i[0];
  assign dma_tx_ready_o = tx_fifo_ready && !tx_apb_write;
  assign tx_dma_push = dma_tx_valid_i && dma_tx_ready_o;
  assign tx_direct_start = (tx_apb_write || tx_dma_push) && tx_fifo_ready &&
                           tx_fifo_empty && tx_engine_ready;
  assign tx_fifo_push  = (tx_apb_write || tx_dma_push) && tx_fifo_ready &&
                         !tx_direct_start;
  assign tx_start      = tx_direct_start || tx_fifo_pop;
  assign tx_data       = tx_direct_start ? (tx_apb_write ? pwdata_i[7:0] : dma_tx_data_i) :
                         tx_fifo_q[tx_rd_ptr_q];

  // A simultaneous RXDATA read can make room for an arriving byte.
  assign rx_fifo_pop   = apb_access && !pwrite_i && !pslverr_o &&
                         (reg_offset == REG_RXDATA) && !rx_fifo_empty;
  assign rx_fifo_push  = rx_byte_valid && (!rx_fifo_full || rx_fifo_pop);

  assign tx_watermark_pending = (tx_count_q <= tx_watermark_q);
  assign rx_watermark_pending = !rx_fifo_empty &&
                                ((rx_watermark_q == '0) || (rx_count_q >= rx_watermark_q));
  assign irq_status_value = {29'h00000000, rx_overrun_q, tx_watermark_pending,
                             rx_watermark_pending};
  assign irq_status_clear = apb_access && pwrite_i && !pslverr_o &&
                            (reg_offset == REG_IRQ_STATUS) && pstrb_i[0] && pwdata_i[2];

  assign status_value = {28'h0000000, rx_overrun_q, (tx_engine_busy | !tx_fifo_empty),
                         !rx_fifo_empty, tx_fifo_ready};
  assign irq_o = (rx_watermark_pending && ctrl_q[2]) ||
                 (tx_watermark_pending && ctrl_q[3]) ||
                 (rx_overrun_q && ctrl_q[4]);
  assign busy_o = tx_engine_busy | !tx_fifo_empty;

  uart_baudgen uart_baudgen_i (
    .clk       (pclk),
    .rst_n     (presetn),
    .enable_i  (ctrl_q[0] | ctrl_q[1]),
    .divisor_i (baud_div_q),
    .tick_o    (baud_tick)
  );

  uart_tx uart_tx_i (
    .clk          (pclk),
    .rst_n        (presetn),
    .baud_tick_i  (baud_tick),
    .tx_enable_i  (ctrl_q[0]),
    .start_i      (tx_start),
    .data_i       (tx_data),
    .tx_o         (uart_tx_o),
    .busy_o       (tx_engine_busy),
    .ready_o      (tx_engine_ready)
  );

  uart_rx uart_rx_i_inst (
    .clk         (pclk),
    .rst_n       (presetn),
    .rx_i        (uart_rx_i),
    .rx_enable_i (ctrl_q[1]),
    .divisor_i   (baud_div_q),
    .valid_o     (rx_byte_valid),
    .data_o      (rx_byte)
  );

  always_comb begin
    unique case (reg_offset)
      REG_TXDATA:       prdata_o = 32'h0000_0000;
      REG_RXDATA:       prdata_o = {24'h000000, rx_fifo_empty ? 8'h00 : rx_fifo_q[rx_rd_ptr_q]};
      REG_STATUS:       prdata_o = status_value;
      REG_BAUDDIV:      prdata_o = baud_div_q;
      REG_CTRL:         prdata_o = ctrl_q;
      REG_TX_WATERMARK: prdata_o = {{(32-TX_FIFO_COUNT_WIDTH){1'b0}}, tx_watermark_q};
      REG_RX_WATERMARK: prdata_o = {{(32-RX_FIFO_COUNT_WIDTH){1'b0}}, rx_watermark_q};
      REG_IRQ_STATUS:   prdata_o = irq_status_value;
      default:          prdata_o = 32'h0000_0000;
    endcase
  end

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      tx_rd_ptr_q     <= '0;
      tx_wr_ptr_q     <= '0;
      tx_count_q      <= '0;
      tx_watermark_q  <= DEFAULT_TX_WATERMARK;
    end else begin
      if (!ctrl_q[0]) begin
        tx_rd_ptr_q <= '0;
        tx_wr_ptr_q <= '0;
        tx_count_q  <= '0;
      end else begin
        if (tx_fifo_push) begin
          tx_fifo_q[tx_wr_ptr_q] <= tx_apb_write ? pwdata_i[7:0] : dma_tx_data_i;
          if (tx_wr_ptr_q == TX_FIFO_LAST_ADDR) begin
            tx_wr_ptr_q <= '0;
          end else begin
            tx_wr_ptr_q <= tx_wr_ptr_q + 1'b1;
          end
        end
        if (tx_fifo_pop) begin
          if (tx_rd_ptr_q == TX_FIFO_LAST_ADDR) begin
            tx_rd_ptr_q <= '0;
          end else begin
            tx_rd_ptr_q <= tx_rd_ptr_q + 1'b1;
          end
        end
        unique case ({tx_fifo_push, tx_fifo_pop})
          2'b10: tx_count_q <= tx_count_q + 1'b1;
          2'b01: tx_count_q <= tx_count_q - 1'b1;
          default: begin
          end
        endcase
      end
      if (apb_access && pwrite_i && !pslverr_o && (reg_offset == REG_TX_WATERMARK)) begin
        tx_watermark_q <= clamp_tx_watermark(pwdata_i);
      end
    end
  end

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      rx_rd_ptr_q     <= '0;
      rx_wr_ptr_q     <= '0;
      rx_count_q      <= '0;
      rx_watermark_q  <= DEFAULT_RX_WATERMARK;
      rx_overrun_q    <= 1'b0;
    end else begin
      if (rx_fifo_push) begin
        rx_fifo_q[rx_wr_ptr_q] <= rx_byte;
        if (rx_wr_ptr_q == RX_FIFO_LAST_ADDR) begin
          rx_wr_ptr_q <= '0;
        end else begin
          rx_wr_ptr_q <= rx_wr_ptr_q + 1'b1;
        end
      end
      if (rx_fifo_pop) begin
        if (rx_rd_ptr_q == RX_FIFO_LAST_ADDR) begin
          rx_rd_ptr_q <= '0;
        end else begin
          rx_rd_ptr_q <= rx_rd_ptr_q + 1'b1;
        end
      end
      unique case ({rx_fifo_push, rx_fifo_pop})
        2'b10: rx_count_q <= rx_count_q + 1'b1;
        2'b01: rx_count_q <= rx_count_q - 1'b1;
        default: begin
        end
      endcase

      if (irq_status_clear) begin
        rx_overrun_q <= 1'b0;
      end
      if (rx_byte_valid && !rx_fifo_push) begin
        rx_overrun_q <= 1'b1;
      end
      if (apb_access && pwrite_i && !pslverr_o && (reg_offset == REG_RX_WATERMARK)) begin
        rx_watermark_q <= clamp_rx_watermark(pwdata_i);
      end
    end
  end

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      baud_div_q <= RESET_BAUD_DIV;
      ctrl_q     <= 32'h0000_0003;
    end else if (apb_access && pwrite_i && !pslverr_o) begin
      unique case (reg_offset)
        REG_BAUDDIV: baud_div_q <= pwdata_i;
        REG_CTRL:    ctrl_q     <= pwdata_i;
        default: begin
        end
      endcase
    end
  end

endmodule
