// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

import soc_pkg::*;

// APB interconnect: decodes APB addresses to peripheral select signals
// and multiplexes peripheral responses back to the bridge.
module apb_interconnect (
  // Bridge interface
  input  logic        psel_i,
  input  logic        penable_i,
  input  logic [31:0] paddr_i,

  // UART peripheral
  output logic        uart_psel_o,
  input  logic        uart_pready_i,
  input  logic [31:0] uart_prdata_i,
  input  logic        uart_pslverr_i,

  // GPIO peripheral
  output logic        gpio_psel_o,
  input  logic        gpio_pready_i,
  input  logic [31:0] gpio_prdata_i,
  input  logic        gpio_pslverr_i,

  // Timer peripheral
  output logic        timer_psel_o,
  input  logic        timer_pready_i,
  input  logic [31:0] timer_prdata_i,
  input  logic        timer_pslverr_i,

  // SPI peripheral
  output logic        spi_psel_o,
  input  logic        spi_pready_i,
  input  logic [31:0] spi_prdata_i,
  input  logic        spi_pslverr_i,

  // WDT peripheral
  output logic        wdt_psel_o,
  input  logic        wdt_pready_i,
  input  logic [31:0] wdt_prdata_i,
  input  logic        wdt_pslverr_i,

  // Clock/reset controller (root-clock domain)
  output logic        clk_rst_psel_o,
  input  logic        clk_rst_pready_i,
  input  logic [31:0] clk_rst_prdata_i,
  input  logic        clk_rst_pslverr_i,

  input  logic [4:0]  peri_clk_en_i,
  input  logic [4:0]  peri_rst_n_i,

  // Multiplexed bridge responses
  output logic        pready_o,
  output logic [31:0] prdata_o,
  output logic        pslverr_o
);

  // Unmapped APB decode indicator
  logic unmapped_apb_sel;

  // Address decoding: generate peripheral select signals
  assign uart_psel_o      = psel_i & is_uart0_addr(paddr_i) & peri_clk_en_i[0] & peri_rst_n_i[0];
  assign spi_psel_o       = psel_i & is_spi0_addr(paddr_i) & peri_clk_en_i[1] & peri_rst_n_i[1];
  assign timer_psel_o     = psel_i & is_timer0_addr(paddr_i) & peri_clk_en_i[2] & peri_rst_n_i[2];
  assign gpio_psel_o      = psel_i & is_gpio0_addr(paddr_i) & peri_clk_en_i[3] & peri_rst_n_i[3];
  assign wdt_psel_o       = psel_i & is_wdt0_addr(paddr_i) & peri_clk_en_i[4] & peri_rst_n_i[4];
  assign clk_rst_psel_o   = psel_i & is_clk_rst_ctrl_addr(paddr_i);
  assign unmapped_apb_sel = psel_i & !is_uart0_addr(paddr_i) & !is_gpio0_addr(paddr_i) &
                            !is_timer0_addr(paddr_i) &
                            !is_spi0_addr(paddr_i) &
                            !is_wdt0_addr(paddr_i) &
                            !is_clk_rst_ctrl_addr(paddr_i);

  // Response multiplexing: route responses from selected peripheral to bridge
  assign pready_o = uart_psel_o  ? uart_pready_i :
                    gpio_psel_o  ? gpio_pready_i :
                    timer_psel_o ? timer_pready_i :
                    spi_psel_o   ? spi_pready_i :
                    wdt_psel_o   ? wdt_pready_i :
                    clk_rst_psel_o ? clk_rst_pready_i :
                    1'b1;

  assign prdata_o = uart_psel_o  ? uart_prdata_i :
                    gpio_psel_o  ? gpio_prdata_i :
                    timer_psel_o ? timer_prdata_i :
                    spi_psel_o   ? spi_prdata_i :
                    wdt_psel_o   ? wdt_prdata_i :
                    clk_rst_psel_o ? clk_rst_prdata_i :
                    32'h0000_0000;

  assign pslverr_o = (uart_psel_o  & uart_pslverr_i) |
                     (gpio_psel_o  & gpio_pslverr_i) |
                     (timer_psel_o & timer_pslverr_i) |
                     (spi_psel_o   & spi_pslverr_i) |
                     (wdt_psel_o   & wdt_pslverr_i) |
                     (clk_rst_psel_o & clk_rst_pslverr_i) |
                     (unmapped_apb_sel & penable_i);

endmodule
