// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

module spi_apb #(
  parameter logic [31:0] RESET_CLK_DIV = 32'd2
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

  output logic        spi_sclk_o,
  output logic        spi_mosi_o,
  input  logic        spi_miso_i,
  output logic [3:0]  spi_ss_o,
  output logic        irq_o,
  output logic        busy_o
);

  localparam logic [7:0] REG_TXDATA = 8'h00;
  localparam logic [7:0] REG_RXDATA = 8'h04;
  localparam logic [7:0] REG_STATUS = 8'h08;
  localparam logic [7:0] REG_CLKDIV = 8'h0c;
  localparam logic [7:0] REG_CTRL   = 8'h10;
  localparam logic [7:0] REG_SS     = 8'h14;

  logic        apb_access;
  logic [7:0]  reg_offset;
  logic [31:0] ctrl_q;
  logic [31:0] clk_div_q;
  logic [3:0]  ss_q;
  logic [7:0]  tx_shift_q;
  logic [7:0]  rx_shift_q;
  logic [7:0]  rx_data_q;
  logic [31:0] div_count_q;
  logic [3:0]  bit_count_q;
  logic        busy_q;
  logic        done_q;
  logic        finish_q;
  logic        sclk_q;
  logic        mosi_q;
  logic        start_transfer;
  logic        sample_edge;
  logic        shift_edge;
  logic [7:0]  status_value;

  assign apb_access = psel_i & penable_i;
  assign reg_offset = paddr_i[7:0];
  assign pready_o   = 1'b1;
  assign pslverr_o  = apb_access &&
                      (reg_offset != REG_TXDATA) &&
                      (reg_offset != REG_RXDATA) &&
                      (reg_offset != REG_STATUS) &&
                      (reg_offset != REG_CLKDIV) &&
                      (reg_offset != REG_CTRL) &&
                      (reg_offset != REG_SS);

  assign start_transfer = apb_access && pwrite_i && !pslverr_o &&
                          (reg_offset == REG_TXDATA) && pstrb_i[0] &&
                          ctrl_q[0] && !busy_q;
  assign status_value = {4'h0, done_q, done_q, busy_q, !busy_q};
  assign irq_o = done_q & ctrl_q[1];
  assign busy_o = busy_q;
  assign spi_sclk_o = busy_q ? sclk_q : ctrl_q[2];
  assign spi_mosi_o = mosi_q;
  assign spi_ss_o = ss_q;

  always_comb begin
    unique case (reg_offset)
      REG_TXDATA: prdata_o = 32'h0000_0000;
      REG_RXDATA: prdata_o = {24'h000000, rx_data_q};
      REG_STATUS: prdata_o = {24'h000000, status_value};
      REG_CLKDIV: prdata_o = clk_div_q;
      REG_CTRL:   prdata_o = ctrl_q;
      REG_SS:     prdata_o = {28'h0000000, ss_q};
      default:    prdata_o = 32'h0000_0000;
    endcase
  end

  always_comb begin
    sample_edge = ctrl_q[3] ? (sclk_q != ctrl_q[2]) : (sclk_q == ctrl_q[2]);
    shift_edge  = !sample_edge;
  end

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      ctrl_q      <= 32'h0000_0001;
      clk_div_q   <= RESET_CLK_DIV;
      ss_q        <= 4'hf;
      tx_shift_q  <= 8'h00;
      rx_shift_q  <= 8'h00;
      rx_data_q   <= 8'h00;
      div_count_q <= 32'h0000_0000;
      bit_count_q <= 4'h0;
      busy_q      <= 1'b0;
      done_q      <= 1'b0;
      finish_q    <= 1'b0;
      sclk_q      <= 1'b0;
      mosi_q      <= 1'b0;
    end else begin
      if (apb_access && pwrite_i && !pslverr_o) begin
        unique case (reg_offset)
          REG_CLKDIV: begin
            clk_div_q <= (pwdata_i == 32'h0000_0000) ? 32'h0000_0001 : pwdata_i;
          end
          REG_CTRL: begin
            ctrl_q <= pwdata_i;
            if (pstrb_i[0] && pwdata_i[4]) begin
              done_q <= 1'b0;
            end
          end
          REG_SS: begin
            ss_q <= pwdata_i[3:0];
          end
          default: begin
          end
        endcase
      end

      if (start_transfer) begin
        busy_q      <= 1'b1;
        done_q      <= 1'b0;
        finish_q    <= 1'b0;
        tx_shift_q  <= pwdata_i[7:0];
        rx_shift_q  <= 8'h00;
        div_count_q <= 32'h0000_0000;
        bit_count_q <= 4'h0;
        sclk_q      <= ctrl_q[2];
        mosi_q      <= ctrl_q[5] ? pwdata_i[0] : pwdata_i[7];
      end else if (busy_q) begin
        if (finish_q) begin
          busy_q <= 1'b0;
          done_q <= 1'b1;
          finish_q <= 1'b0;
          sclk_q <= ctrl_q[2];
        end else if (div_count_q >= (clk_div_q - 32'h0000_0001)) begin
          div_count_q <= 32'h0000_0000;
          sclk_q <= ~sclk_q;

          if (sample_edge) begin
            if (ctrl_q[5]) begin
              rx_shift_q <= {spi_miso_i, rx_shift_q[7:1]};
              if (bit_count_q == 4'd7) begin
                rx_data_q <= {spi_miso_i, rx_shift_q[7:1]};
              end
            end else begin
              rx_shift_q <= {rx_shift_q[6:0], spi_miso_i};
              if (bit_count_q == 4'd7) begin
                rx_data_q <= {rx_shift_q[6:0], spi_miso_i};
              end
            end
            if (bit_count_q == 4'd7) begin
              finish_q <= 1'b1;
            end else begin
              bit_count_q <= bit_count_q + 4'h1;
            end
          end else if (shift_edge) begin
            if (ctrl_q[5]) begin
              tx_shift_q <= {1'b0, tx_shift_q[7:1]};
              mosi_q <= tx_shift_q[1];
            end else begin
              tx_shift_q <= {tx_shift_q[6:0], 1'b0};
              mosi_q <= tx_shift_q[6];
            end
          end
        end else begin
          div_count_q <= div_count_q + 32'h0000_0001;
        end
      end
    end
  end

endmodule
