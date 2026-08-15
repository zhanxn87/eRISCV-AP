// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// AP-local APB decoder.  It deliberately has no dependency on the M2 soc_pkg
// or its clock-gating policy; all APB transfers run in the AP root clock
// domain and unmapped accesses complete with PSLVERR.
module ap_apb_interconnect
  import ap_soc_pkg::*;
(
  input logic psel_i,
  input logic penable_i,
  input logic [AP_PADDR_W-1:0] paddr_i,

  output logic uart_psel_o,
  input logic uart_pready_i,
  input logic [31:0] uart_prdata_i,
  input logic uart_pslverr_i,

  output logic spi_psel_o,
  input logic spi_pready_i,
  input logic [31:0] spi_prdata_i,
  input logic spi_pslverr_i,

  output logic timer_psel_o,
  input logic timer_pready_i,
  input logic [31:0] timer_prdata_i,
  input logic timer_pslverr_i,

  output logic gpio_psel_o,
  input logic gpio_pready_i,
  input logic [31:0] gpio_prdata_i,
  input logic gpio_pslverr_i,

  output logic pready_o,
  output logic [31:0] prdata_o,
  output logic pslverr_o
);

  logic uart_hit;
  logic spi_hit;
  logic timer_hit;
  logic gpio_hit;
  logic unmapped_hit;

  assign uart_hit = ap_addr_in_range(paddr_i, AP_UART0_BASE,
                                     AP_UART0_BASE + AP_APB_PERIPH_SIZE);
  assign spi_hit = ap_addr_in_range(paddr_i, AP_SPI0_BASE,
                                    AP_SPI0_BASE + AP_APB_PERIPH_SIZE);
  assign timer_hit = ap_addr_in_range(paddr_i, AP_TIMER0_BASE,
                                      AP_TIMER0_BASE + AP_APB_PERIPH_SIZE);
  assign gpio_hit = ap_addr_in_range(paddr_i, AP_GPIO0_BASE,
                                     AP_GPIO0_BASE + AP_APB_PERIPH_SIZE);
  assign uart_psel_o = psel_i && uart_hit;
  assign spi_psel_o = psel_i && spi_hit;
  assign timer_psel_o = psel_i && timer_hit;
  assign gpio_psel_o = psel_i && gpio_hit;
  assign unmapped_hit = psel_i && !(uart_hit || spi_hit || timer_hit || gpio_hit);

  always_comb begin
    pready_o = 1'b1;
    prdata_o = '0;
    pslverr_o = unmapped_hit && penable_i;
    if (uart_psel_o) begin
      pready_o = uart_pready_i;
      prdata_o = uart_prdata_i;
      pslverr_o = uart_pslverr_i;
    end else if (spi_psel_o) begin
      pready_o = spi_pready_i;
      prdata_o = spi_prdata_i;
      pslverr_o = spi_pslverr_i;
    end else if (timer_psel_o) begin
      pready_o = timer_pready_i;
      prdata_o = timer_prdata_i;
      pslverr_o = timer_pslverr_i;
    end else if (gpio_psel_o) begin
      pready_o = gpio_pready_i;
      prdata_o = gpio_prdata_i;
      pslverr_o = gpio_pslverr_i;
    end
  end

endmodule
