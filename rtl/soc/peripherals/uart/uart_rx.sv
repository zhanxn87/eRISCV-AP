// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

module uart_rx (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        rx_i,
  input  logic        rx_enable_i,
  input  logic [31:0] divisor_i,
  output logic        valid_o,
  output logic [7:0]  data_o
);

  typedef enum logic [1:0] {
    RX_IDLE,
    RX_START,
    RX_DATA,
    RX_STOP
  } rx_state_t;

  rx_state_t   state_q;
  logic [31:0] count_q;
  logic [31:0] bit_period;
  logic [31:0] half_period;
  logic [2:0]  bit_index_q;
  logic [7:0]  data_shift_q;
  logic        rx_meta_q;
  logic        rx_sync_q;

  assign bit_period  = (divisor_i == 32'h0000_0000) ? 32'h0000_0001 : divisor_i;
  assign half_period = bit_period >> 1;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_meta_q <= 1'b1;
      rx_sync_q <= 1'b1;
    end else begin
      rx_meta_q <= rx_i;
      rx_sync_q <= rx_meta_q;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q      <= RX_IDLE;
      count_q      <= 32'h0000_0000;
      bit_index_q  <= 3'd0;
      data_shift_q <= 8'h00;
      valid_o      <= 1'b0;
      data_o       <= 8'h00;
    end else begin
      valid_o <= 1'b0;
      if (!rx_enable_i) begin
        state_q     <= RX_IDLE;
        count_q     <= 32'h0000_0000;
        bit_index_q <= 3'd0;
      end else begin
        unique case (state_q)
          RX_IDLE: begin
            count_q <= 32'h0000_0000;
            if (!rx_sync_q) begin
              state_q <= RX_START;
              count_q <= half_period;
            end
          end

          RX_START: begin
            if (count_q == 32'h0000_0000) begin
              if (!rx_sync_q) begin
                state_q     <= RX_DATA;
                count_q     <= bit_period - 32'h0000_0001;
                bit_index_q <= 3'd0;
              end else begin
                state_q <= RX_IDLE;
              end
            end else begin
              count_q <= count_q - 32'h0000_0001;
            end
          end

          RX_DATA: begin
            if (count_q == 32'h0000_0000) begin
              data_shift_q[bit_index_q] <= rx_sync_q;
              count_q <= bit_period - 32'h0000_0001;
              if (bit_index_q == 3'd7) begin
                state_q <= RX_STOP;
              end else begin
                bit_index_q <= bit_index_q + 3'd1;
              end
            end else begin
              count_q <= count_q - 32'h0000_0001;
            end
          end

          RX_STOP: begin
            if (count_q == 32'h0000_0000) begin
              if (rx_sync_q) begin
                data_o  <= data_shift_q;
                valid_o <= 1'b1;
              end
              state_q <= RX_IDLE;
            end else begin
              count_q <= count_q - 32'h0000_0001;
            end
          end

          default: begin
            state_q <= RX_IDLE;
          end
        endcase
      end
    end
  end

endmodule
