// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// VCU108 board wrapper for eRISCV-M2.
// The board 300 MHz differential clock is converted to the 100 MHz SoC clock.
module eriscv_m2_vcu108_wrapper (
  input  wire       sys_clk_p,
  input  wire       sys_clk_n,
  input  wire       cpu_reset_i,
  input  wire       uart_rx_i,
  output wire       uart_tx_o,
  input  wire [2:0] boot_mode_i,
  output wire       boot_uart_overrun_led_o,
  output wire       boot_uart_protocol_error_led_o
);

  wire       sys_clk_ibuf;
  wire       sys_clk;
  wire       soc_clk_mmcm;
  wire       soc_clk_fb;
  wire       soc_clk_fb_buf;
  wire       soc_clk_locked;
  wire       soc_clk;
  wire       soc_reset_n;
  logic [2:0] reset_sync;
  logic [1:0] fetch_enable_sync;
  logic       soc_rst_n;
  logic       fetch_enable;
  logic [31:0] gpio_o;
  logic [31:0] gpio_oe;
  logic        spi_sclk;
  logic        spi_mosi;
  logic [3:0]  spi_ss;
  logic        jtag_tck;
  logic        jtag_tms;
  logic        jtag_tdi;
  logic        jtag_tdo;
  logic        jtag_tap_reset;
  logic        boot_uart_overrun;
  logic        boot_uart_protocol_error;

  IBUFDS #(
    .DIFF_TERM("FALSE"),
    .IBUF_LOW_PWR("FALSE")
  ) sys_clk_ibufds_i (
    .I(sys_clk_p),
    .IB(sys_clk_n),
    .O(sys_clk_ibuf)
  );

  BUFG sys_clk_bufg_i (
    .I(sys_clk_ibuf),
    .O(sys_clk)
  );

  // VCU108 sysclk1 is 300 MHz. Generate the 100 MHz M1 implementation clock.
  MMCME3_BASE #(
    .BANDWIDTH("OPTIMIZED"),
    .CLKFBOUT_MULT_F(3.000),
    .CLKFBOUT_PHASE(0.000),
    .CLKIN1_PERIOD(3.333),
    .CLKOUT0_DIVIDE_F(9.000),
    .CLKOUT0_DUTY_CYCLE(0.500),
    .CLKOUT0_PHASE(0.000),
    .DIVCLK_DIVIDE(1),
    .REF_JITTER1(0.010),
    .STARTUP_WAIT("FALSE")
  ) soc_clk_mmcm_i (
    .CLKIN1(sys_clk),
    .CLKFBIN(soc_clk_fb_buf),
    .RST(cpu_reset_i),
    .PWRDWN(1'b0),
    .CLKFBOUT(soc_clk_fb),
    .CLKOUT0(soc_clk_mmcm),
    .LOCKED(soc_clk_locked),
    .CLKFBOUTB(), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(),
    .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(),
    .CLKOUT6()
  );

  BUFG soc_clk_fb_bufg_i (.I(soc_clk_fb), .O(soc_clk_fb_buf));
  BUFG soc_clk_bufg_i (.I(soc_clk_mmcm), .O(soc_clk));

  assign soc_reset_n = !cpu_reset_i && soc_clk_locked;

  // Assert asynchronously, release reset and fetch synchronously in the SoC domain.
  always_ff @(posedge soc_clk or negedge soc_reset_n) begin
    if (!soc_reset_n)
      reset_sync <= 3'b000;
    else
      reset_sync <= {reset_sync[1:0], 1'b1};
  end
  assign soc_rst_n = reset_sync[2];

  always_ff @(posedge soc_clk or negedge soc_rst_n) begin
    if (!soc_rst_n)
      fetch_enable_sync <= 2'b00;
    else
      fetch_enable_sync <= {fetch_enable_sync[0], 1'b1};
  end
  assign fetch_enable = fetch_enable_sync[1];

  // Use the FPGA configuration JTAG chain for the fabric Debug 1.0 DTM.
  BSCANE2 #(.JTAG_CHAIN(2)) bscan_debug_i (
    .CAPTURE(), .DRCK(), .RESET(jtag_tap_reset), .RUNTEST(), .SEL(), .SHIFT(),
    .TCK(jtag_tck), .TDI(jtag_tdi), .TMS(jtag_tms), .UPDATE(), .TDO(jtag_tdo)
  );

  soc soc_i (
    .clk(soc_clk),
    .rst_n(soc_rst_n),
    .ext_rst_n_i(soc_rst_n),
    .fetch_enable_i(fetch_enable),
    .boot_mode_i(boot_mode_i),
    .boot_uart_rx_i(uart_rx_i),
    .boot_uart_overrun_o(boot_uart_overrun),
    .boot_uart_protocol_error_o(boot_uart_protocol_error),
    .boot_addr_i(32'h1000_0000),
    .uart_rx_i(uart_rx_i),
    .uart_tx_o(uart_tx_o),
    .gpio_i(32'h0000_0000),
    .gpio_o(gpio_o),
    .gpio_oe_o(gpio_oe),
    .spi_sclk_o(spi_sclk),
    .spi_mosi_o(spi_mosi),
    .spi_miso_i(1'b0),
    .spi_ss_o(spi_ss),
    .jtag_tck_i(jtag_tck),
    .jtag_tms_i(jtag_tms),
    .jtag_tdi_i(jtag_tdi),
    .jtag_tdo_o(jtag_tdo),
    .jtag_trst_n_i(soc_rst_n && !jtag_tap_reset),
    .ext_irq_i('0)
  );

  assign boot_uart_overrun_led_o = boot_uart_overrun;
  assign boot_uart_protocol_error_led_o = boot_uart_protocol_error;

endmodule
