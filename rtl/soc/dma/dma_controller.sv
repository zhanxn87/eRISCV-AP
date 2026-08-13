// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

import soc_pkg::*;

// One generic System SRAM DMA channel. Software chooses a direct System SRAM
// copy, a direct System-SRAM-to-UART-TX byte stream, or a linked descriptor
// chain. Descriptor mode remains System-SRAM-only.
module dma_controller (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        cfg_req_i,
  input  logic        cfg_we_i,
  input  logic [31:0] cfg_addr_i,
  input  logic [31:0] cfg_wdata_i,
  output logic        cfg_resp_valid_o,
  output logic [31:0] cfg_rdata_o,
  output logic        cfg_err_o,

  output logic        dma_req_valid_o,
  output logic        dma_req_we_o,
  output logic [3:0]  dma_req_be_o,
  output logic [31:0] dma_req_addr_o,
  output logic [31:0] dma_req_wdata_o,
  input  logic        dma_req_ready_i,
  input  logic        dma_resp_valid_i,
  input  logic [31:0] dma_resp_rdata_i,
  input  logic        dma_resp_err_i,

  output logic        uart_tx_valid_o,
  output logic [7:0]  uart_tx_data_o,
  input  logic        uart_tx_ready_i,

  output logic        irq_o
);

  localparam logic [5:0] REG_CTRL      = 6'h00;
  localparam logic [5:0] REG_STATUS    = 6'h04;
  localparam logic [5:0] REG_SRC       = 6'h08;
  localparam logic [5:0] REG_DST       = 6'h0c;
  localparam logic [5:0] REG_LEN       = 6'h10;
  localparam logic [5:0] REG_DESC_HEAD = 6'h14;

  localparam int unsigned DMA_MAX_DESCRIPTOR_COUNT = 256;
  localparam logic [8:0] DMA_MAX_DESCRIPTOR_COUNT_U9 = 9'(DMA_MAX_DESCRIPTOR_COUNT);
  localparam logic [31:0] DESC_CTRL_OWN     = 32'h0000_0001;
  localparam logic [31:0] DESC_CTRL_IRQ_EN  = 32'h0000_0002;
  localparam logic [31:0] DESC_CTRL_END     = 32'h0000_0004;
  localparam logic [31:0] DESC_CTRL_SRC_INC = 32'h0000_0008;
  localparam logic [31:0] DESC_CTRL_DST_INC = 32'h0000_0010;
  localparam logic [31:0] DESC_STATUS_DONE  = 32'h0000_0001;
  localparam logic [31:0] DESC_STATUS_ERROR = 32'h0000_0002;

  typedef enum logic [3:0] {
    DMA_IDLE,
    DMA_FETCH_REQ, DMA_FETCH_WAIT,
    DMA_READ_REQ, DMA_READ_WAIT, DMA_WRITE_REQ, DMA_WRITE_WAIT,
    DMA_WB_CTRL_REQ, DMA_WB_CTRL_WAIT,
    DMA_WB_STATUS_REQ, DMA_WB_STATUS_WAIT,
    DMA_WB_BYTES_REQ, DMA_WB_BYTES_WAIT,
    DMA_UART_TX_REQ,
    DMA_ABORT_WAIT
  } dma_state_e;

  dma_state_e state_q;
  logic [31:0] src_q, dst_q, len_q, read_data_q, bytes_done_q;
  logic [31:0] desc_head_q, desc_addr_q;
  logic [31:0] desc_next_q, desc_src_q, desc_dst_q, desc_len_q, desc_ctrl_q;
  logic [2:0] fetch_word_q;
  logic [1:0] uart_tx_byte_index_q;
  logic [8:0] descriptor_count_q;
  logic descriptor_active_q, descriptor_error_q, abort_pending_q, uart_tx_mode_q;
  logic abort_write_inflight_q;
  logic irq_enable_q, done_q, error_q, descriptor_irq_q;
  logic cfg_resp_valid_q, cfg_err_q;
  logic [31:0] cfg_rdata_q, cfg_read_data;
  logic abort_request;

  assign abort_request = cfg_req_i && cfg_we_i &&
                         (cfg_addr_i[5:0] == REG_CTRL) && cfg_wdata_i[2];

  function automatic logic is_dma_range_allowed(
    input logic [31:0] addr,
    input logic [31:0] length
  );
    if (length == 32'd0 || length > SYSTEM_SRAM_SIZE_BYTES)
      return 1'b0;
    if (!is_system_sram_addr(addr))
      return 1'b0;
    return (addr - SYSTEM_SRAM_BASE_ADDR) <= (SYSTEM_SRAM_SIZE_BYTES - length);
  endfunction

  function automatic logic is_descriptor_valid(
    input logic [31:0] addr,
    input logic [31:0] next,
    input logic [31:0] source,
    input logic [31:0] destination,
    input logic [31:0] length,
    input logic [31:0] control
  );
    if ((addr[4:0] != 5'd0) || !is_dma_range_allowed(addr, 32'd32))
      return 1'b0;
    if ((control & DESC_CTRL_OWN) == 32'd0 ||
        (control & (DESC_CTRL_SRC_INC | DESC_CTRL_DST_INC)) !=
            (DESC_CTRL_SRC_INC | DESC_CTRL_DST_INC))
      return 1'b0;
    if (((source | destination | length) & 32'd3) != 32'd0 ||
        !is_dma_range_allowed(source, length) ||
        !is_dma_range_allowed(destination, length))
      return 1'b0;
    if (next != 32'd0 &&
        ((next[4:0] != 5'd0) || !is_dma_range_allowed(next, 32'd32)))
      return 1'b0;
    return ((next == 32'd0) == ((control & DESC_CTRL_END) != 32'd0));
  endfunction

  always_comb begin
    unique case (cfg_addr_i[5:0])
      REG_CTRL: cfg_read_data = {27'h0, uart_tx_mode_q, 1'b0, 1'b0,
                                 irq_enable_q, 1'b0};
      REG_STATUS: cfg_read_data = {28'h0, descriptor_irq_q, error_q, done_q,
                                   (state_q != DMA_IDLE)};
      REG_SRC: cfg_read_data = src_q;
      REG_DST: cfg_read_data = dst_q;
      REG_LEN: cfg_read_data = len_q;
      REG_DESC_HEAD: cfg_read_data = desc_head_q;
      default: cfg_read_data = 32'h0000_0000;
    endcase
  end

  assign cfg_resp_valid_o = cfg_resp_valid_q;
  assign cfg_rdata_o = cfg_rdata_q;
  assign cfg_err_o = cfg_err_q;

  assign dma_req_valid_o = (state_q == DMA_FETCH_REQ) ||
                           (state_q == DMA_READ_REQ) ||
                           (state_q == DMA_WRITE_REQ) ||
                           (state_q == DMA_WB_CTRL_REQ) ||
                           (state_q == DMA_WB_STATUS_REQ) ||
                           (state_q == DMA_WB_BYTES_REQ);
  assign dma_req_we_o = (state_q == DMA_WRITE_REQ) ||
                        (state_q == DMA_WB_CTRL_REQ) ||
                        (state_q == DMA_WB_STATUS_REQ) ||
                        (state_q == DMA_WB_BYTES_REQ);
  assign dma_req_be_o = 4'hf;
  assign uart_tx_valid_o = (state_q == DMA_UART_TX_REQ);
  assign uart_tx_data_o = read_data_q[8 * uart_tx_byte_index_q +: 8];
  always_comb begin
    dma_req_addr_o = src_q;
    dma_req_wdata_o = read_data_q;
    unique case (state_q)
      DMA_FETCH_REQ: begin
        dma_req_addr_o = desc_addr_q + {27'd0, fetch_word_q, 2'b00};
        dma_req_wdata_o = 32'd0;
      end
      DMA_WRITE_REQ: dma_req_addr_o = dst_q;
      DMA_WB_CTRL_REQ: begin
        dma_req_addr_o = desc_addr_q + 32'h10;
        dma_req_wdata_o = desc_ctrl_q & ~DESC_CTRL_OWN;
      end
      DMA_WB_STATUS_REQ: begin
        dma_req_addr_o = desc_addr_q + 32'h14;
        dma_req_wdata_o = descriptor_error_q ? DESC_STATUS_ERROR : DESC_STATUS_DONE;
      end
      DMA_WB_BYTES_REQ: begin
        dma_req_addr_o = desc_addr_q + 32'h18;
        dma_req_wdata_o = bytes_done_q;
      end
      default: ;
    endcase
  end
  assign irq_o = irq_enable_q && (done_q || error_q || descriptor_irq_q);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= DMA_IDLE;
      src_q <= '0;
      dst_q <= '0;
      len_q <= '0;
      read_data_q <= '0;
      bytes_done_q <= '0;
      desc_head_q <= '0;
      desc_addr_q <= '0;
      desc_next_q <= '0;
      desc_src_q <= '0;
      desc_dst_q <= '0;
      desc_len_q <= '0;
      desc_ctrl_q <= '0;
      fetch_word_q <= '0;
      uart_tx_byte_index_q <= '0;
      descriptor_count_q <= '0;
      descriptor_active_q <= 1'b0;
      descriptor_error_q <= 1'b0;
      abort_pending_q <= 1'b0;
      uart_tx_mode_q <= 1'b0;
      abort_write_inflight_q <= 1'b0;
      irq_enable_q <= 1'b0;
      done_q <= 1'b0;
      error_q <= 1'b0;
      descriptor_irq_q <= 1'b0;
      cfg_resp_valid_q <= 1'b0;
      cfg_err_q <= 1'b0;
      cfg_rdata_q <= '0;
    end else begin
      cfg_resp_valid_q <= 1'b0;
      if (cfg_req_i && !cfg_resp_valid_q) begin
        cfg_resp_valid_q <= 1'b1;
        cfg_rdata_q <= cfg_read_data;
        cfg_err_q <= cfg_we_i && (state_q != DMA_IDLE) &&
                     ((cfg_addr_i[5:0] == REG_SRC) || (cfg_addr_i[5:0] == REG_DST) ||
                      (cfg_addr_i[5:0] == REG_LEN) ||
                      (cfg_addr_i[5:0] == REG_DESC_HEAD));
        if (cfg_we_i) begin
          unique case (cfg_addr_i[5:0])
            REG_CTRL: begin
              irq_enable_q <= cfg_wdata_i[1];
              uart_tx_mode_q <= cfg_wdata_i[4];
              if (cfg_wdata_i[2]) begin
                if (state_q != DMA_IDLE) begin
                  done_q <= 1'b0;
                  error_q <= 1'b1;
                  abort_pending_q <= 1'b1;
                end
              end else if (cfg_wdata_i[3] && (state_q == DMA_IDLE)) begin
                done_q <= 1'b0;
                error_q <= 1'b0;
                descriptor_irq_q <= 1'b0;
                descriptor_count_q <= '0;
                descriptor_active_q <= 1'b1;
                abort_pending_q <= 1'b0;
                if (cfg_wdata_i[4] || (desc_head_q[4:0] != 5'd0) ||
                    !is_dma_range_allowed(desc_head_q, 32'd32)) begin
                  error_q <= 1'b1;
                  descriptor_active_q <= 1'b0;
                end else begin
                  desc_addr_q <= desc_head_q;
                  fetch_word_q <= 3'd0;
                  state_q <= DMA_FETCH_REQ;
                end
              end else if (cfg_wdata_i[0] && (state_q == DMA_IDLE)) begin
                done_q <= 1'b0;
                error_q <= 1'b0;
                descriptor_irq_q <= 1'b0;
                descriptor_active_q <= 1'b0;
                abort_pending_q <= 1'b0;
                uart_tx_byte_index_q <= '0;
                if (cfg_wdata_i[4] ?
                    ((len_q == 32'd0) || (|src_q[1:0]) ||
                     !is_dma_range_allowed(src_q, len_q) ||
                     (dst_q != UART0_BASE)) :
                    ((len_q == 32'd0) || (|src_q[1:0]) || (|dst_q[1:0]) ||
                     (|len_q[1:0]) || !is_dma_range_allowed(src_q, len_q) ||
                     !is_dma_range_allowed(dst_q, len_q)))
                  error_q <= 1'b1;
                else begin
                  bytes_done_q <= 32'd0;
                  state_q <= DMA_READ_REQ;
                end
              end
            end
            REG_STATUS: begin
              if (cfg_wdata_i[1]) done_q <= 1'b0;
              if (cfg_wdata_i[2]) error_q <= 1'b0;
              if (cfg_wdata_i[3]) descriptor_irq_q <= 1'b0;
            end
            REG_SRC: if (state_q == DMA_IDLE) src_q <= cfg_wdata_i;
            REG_DST: if (state_q == DMA_IDLE) dst_q <= cfg_wdata_i;
            REG_LEN: if (state_q == DMA_IDLE) len_q <= cfg_wdata_i;
            REG_DESC_HEAD: if (state_q == DMA_IDLE) desc_head_q <= cfg_wdata_i;
            default: ;
          endcase
        end
      end

      unique case (state_q)
        DMA_FETCH_REQ: if (dma_req_ready_i) state_q <= DMA_FETCH_WAIT;
        DMA_FETCH_WAIT: if (dma_resp_valid_i) begin
          if (dma_resp_err_i) begin
            error_q <= 1'b1;
            descriptor_active_q <= 1'b0;
            state_q <= DMA_IDLE;
          end else if (fetch_word_q == 3'd7) begin
            if ((desc_ctrl_q & DESC_CTRL_OWN) == 32'd0) begin
              error_q <= 1'b1;
              descriptor_active_q <= 1'b0;
              abort_pending_q <= 1'b0;
              state_q <= DMA_IDLE;
            end else if (abort_pending_q || abort_request ||
                         descriptor_count_q == DMA_MAX_DESCRIPTOR_COUNT_U9 ||
                         !is_descriptor_valid(desc_addr_q, desc_next_q, desc_src_q,
                                              desc_dst_q, desc_len_q, desc_ctrl_q)) begin
              descriptor_error_q <= 1'b1;
              bytes_done_q <= 32'd0;
              state_q <= DMA_WB_CTRL_REQ;
            end else begin
              descriptor_count_q <= descriptor_count_q + 9'd1;
              src_q <= desc_src_q;
              dst_q <= desc_dst_q;
              len_q <= desc_len_q;
              bytes_done_q <= 32'd0;
              descriptor_error_q <= 1'b0;
              state_q <= DMA_READ_REQ;
            end
          end else begin
            unique case (fetch_word_q)
              3'd0: desc_next_q <= dma_resp_rdata_i;
              3'd1: desc_src_q <= dma_resp_rdata_i;
              3'd2: desc_dst_q <= dma_resp_rdata_i;
              3'd3: desc_len_q <= dma_resp_rdata_i;
              3'd4: desc_ctrl_q <= dma_resp_rdata_i;
              default: ;
            endcase
            fetch_word_q <= fetch_word_q + 3'd1;
            state_q <= DMA_FETCH_REQ;
          end
        end
        DMA_READ_REQ: begin
          if (abort_pending_q || abort_request) begin
            descriptor_error_q <= 1'b1;
            if (dma_req_ready_i) begin
              abort_write_inflight_q <= 1'b0;
              state_q <= DMA_ABORT_WAIT;
            end else if (descriptor_active_q) begin
              state_q <= DMA_WB_CTRL_REQ;
            end else begin
              abort_pending_q <= 1'b0;
              state_q <= DMA_IDLE;
            end
          end else if (dma_req_ready_i) begin
            state_q <= DMA_READ_WAIT;
          end
        end
        DMA_READ_WAIT: if (dma_resp_valid_i) begin
          if (abort_pending_q || abort_request) begin
            descriptor_error_q <= 1'b1;
            if (descriptor_active_q) begin
              state_q <= DMA_WB_CTRL_REQ;
            end else begin
              abort_pending_q <= 1'b0;
              state_q <= DMA_IDLE;
            end
          end else if (dma_resp_err_i) begin
            error_q <= 1'b1;
            if (descriptor_active_q) begin
              descriptor_error_q <= 1'b1;
              state_q <= DMA_WB_CTRL_REQ;
            end else begin
              state_q <= DMA_IDLE;
            end
          end else begin
            read_data_q <= dma_resp_rdata_i;
            state_q <= uart_tx_mode_q ? DMA_UART_TX_REQ : DMA_WRITE_REQ;
          end
        end
        DMA_UART_TX_REQ: begin
          if (abort_pending_q || abort_request) begin
            error_q <= 1'b1;
            abort_pending_q <= 1'b0;
            state_q <= DMA_IDLE;
          end else if (uart_tx_ready_i) begin
            bytes_done_q <= bytes_done_q + 32'd1;
            if (len_q == 32'd1) begin
              len_q <= '0;
              done_q <= 1'b1;
              state_q <= DMA_IDLE;
            end else if (uart_tx_byte_index_q == 2'd3) begin
              src_q <= src_q + 32'd4;
              len_q <= len_q - 32'd1;
              uart_tx_byte_index_q <= '0;
              state_q <= DMA_READ_REQ;
            end else begin
              len_q <= len_q - 32'd1;
              uart_tx_byte_index_q <= uart_tx_byte_index_q + 2'd1;
            end
          end
        end
        DMA_WRITE_REQ: begin
          if (abort_pending_q || abort_request) begin
            descriptor_error_q <= 1'b1;
            if (dma_req_ready_i) begin
              abort_write_inflight_q <= 1'b1;
              state_q <= DMA_ABORT_WAIT;
            end else if (descriptor_active_q) begin
              state_q <= DMA_WB_CTRL_REQ;
            end else begin
              abort_pending_q <= 1'b0;
              state_q <= DMA_IDLE;
            end
          end else if (dma_req_ready_i) begin
            state_q <= DMA_WRITE_WAIT;
          end
        end
        DMA_WRITE_WAIT: if (dma_resp_valid_i) begin
          if (abort_pending_q || abort_request) begin
            if (!dma_resp_err_i) begin
              src_q <= src_q + 32'd4;
              dst_q <= dst_q + 32'd4;
              len_q <= len_q - 32'd4;
              bytes_done_q <= bytes_done_q + 32'd4;
            end
            descriptor_error_q <= 1'b1;
            if (descriptor_active_q) begin
              state_q <= DMA_WB_CTRL_REQ;
            end else begin
              abort_pending_q <= 1'b0;
              state_q <= DMA_IDLE;
            end
          end else if (dma_resp_err_i) begin
            error_q <= 1'b1;
            if (descriptor_active_q) begin
              descriptor_error_q <= 1'b1;
              state_q <= DMA_WB_CTRL_REQ;
            end else begin
              state_q <= DMA_IDLE;
            end
          end else begin
            src_q <= src_q + 32'd4;
            dst_q <= dst_q + 32'd4;
            len_q <= len_q - 32'd4;
            bytes_done_q <= bytes_done_q + 32'd4;
            if (len_q == 32'd4) begin
              if (descriptor_active_q) begin
                descriptor_error_q <= 1'b0;
                state_q <= DMA_WB_CTRL_REQ;
              end else begin
                done_q <= 1'b1;
                state_q <= DMA_IDLE;
              end
            end else begin
              state_q <= DMA_READ_REQ;
            end
          end
        end
        DMA_WB_CTRL_REQ: begin
          if (abort_pending_q || abort_request) begin
            descriptor_error_q <= 1'b1;
            if (dma_req_ready_i) begin
              abort_write_inflight_q <= 1'b0;
              state_q <= DMA_ABORT_WAIT;
            end
          end else if (dma_req_ready_i) begin
            state_q <= DMA_WB_CTRL_WAIT;
          end
        end
        DMA_WB_CTRL_WAIT: if (dma_resp_valid_i) begin
          if (abort_pending_q || abort_request) begin
            descriptor_error_q <= 1'b1;
            state_q <= DMA_WB_CTRL_REQ;
          end else if (dma_resp_err_i) begin
            error_q <= 1'b1;
            descriptor_active_q <= 1'b0;
            state_q <= DMA_IDLE;
          end else begin
            state_q <= DMA_WB_STATUS_REQ;
          end
        end
        DMA_WB_STATUS_REQ: begin
          if (abort_pending_q || abort_request) begin
            descriptor_error_q <= 1'b1;
            if (dma_req_ready_i) begin
              abort_write_inflight_q <= 1'b0;
              state_q <= DMA_ABORT_WAIT;
            end
          end else if (dma_req_ready_i) begin
            state_q <= DMA_WB_STATUS_WAIT;
          end
        end
        DMA_WB_STATUS_WAIT: if (dma_resp_valid_i) begin
          if (abort_pending_q || abort_request) begin
            descriptor_error_q <= 1'b1;
            state_q <= DMA_WB_CTRL_REQ;
          end else if (dma_resp_err_i) begin
            error_q <= 1'b1;
            descriptor_active_q <= 1'b0;
            state_q <= DMA_IDLE;
          end else begin
            state_q <= DMA_WB_BYTES_REQ;
          end
        end
        DMA_WB_BYTES_REQ: begin
          if (abort_pending_q || abort_request) begin
            descriptor_error_q <= 1'b1;
            if (dma_req_ready_i) begin
              abort_write_inflight_q <= 1'b0;
              state_q <= DMA_ABORT_WAIT;
            end
          end else if (dma_req_ready_i) begin
            state_q <= DMA_WB_BYTES_WAIT;
          end
        end
        DMA_WB_BYTES_WAIT: if (dma_resp_valid_i) begin
          if (abort_pending_q || abort_request) begin
            descriptor_error_q <= 1'b1;
            state_q <= DMA_WB_CTRL_REQ;
          end else if (dma_resp_err_i) begin
            error_q <= 1'b1;
            descriptor_active_q <= 1'b0;
            state_q <= DMA_IDLE;
          end else begin
            if ((desc_ctrl_q & DESC_CTRL_IRQ_EN) != 32'd0)
              descriptor_irq_q <= 1'b1;
            if (descriptor_error_q) begin
              error_q <= 1'b1;
              descriptor_active_q <= 1'b0;
              abort_pending_q <= 1'b0;
              state_q <= DMA_IDLE;
            end else if (desc_next_q == 32'd0) begin
              done_q <= 1'b1;
              descriptor_active_q <= 1'b0;
              abort_pending_q <= 1'b0;
              state_q <= DMA_IDLE;
            end else begin
              desc_addr_q <= desc_next_q;
              fetch_word_q <= 3'd0;
              state_q <= DMA_FETCH_REQ;
            end
          end
        end
        DMA_ABORT_WAIT: if (dma_resp_valid_i) begin
          if (abort_write_inflight_q && !dma_resp_err_i) begin
            src_q <= src_q + 32'd4;
            dst_q <= dst_q + 32'd4;
            len_q <= len_q - 32'd4;
            bytes_done_q <= bytes_done_q + 32'd4;
          end
          abort_write_inflight_q <= 1'b0;
          descriptor_error_q <= 1'b1;
          if (descriptor_active_q) begin
            abort_pending_q <= 1'b0;
            state_q <= DMA_WB_CTRL_REQ;
          end else begin
            abort_pending_q <= 1'b0;
            state_q <= DMA_IDLE;
          end
        end
        default: ;
      endcase
    end
  end

endmodule
