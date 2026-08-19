// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// AP uncached-device subsystem.  ap_axi_periph_xbar separates the local
// APB tree, the physical BPI NOR target, and PULP's DECERR path.  Interrupt outputs
// bypass the APB data plane and feed the hart directly through ap_soc.sv.
`include "axi/assign.svh"

module ap_peripheral_subsystem
  import ap_soc_pkg::*;
#(
  parameter int unsigned BPI_READ_WAIT_CYCLES_P = AP_BPI_READ_WAIT_CYCLES,
  parameter int unsigned BPI_ADV_PULSE_CYCLES_P = AP_BPI_ADV_PULSE_CYCLES,
  parameter bit USE_EMBEDDED_BPI_NOR_P = 1'b1
) (
  input logic clk,
  input logic rst_n,
  input logic eth_irq_i,

  input logic uart_rx_i,
  output logic uart_tx_o,
  input logic [31:0] gpio_i,
  output logic [31:0] gpio_o,
  output logic [31:0] gpio_oe_o,
  input logic spi_miso_i,
  output logic spi_sclk_o,
  output logic spi_mosi_o,
  output logic [3:0] spi_ss_o,

  output logic [63:0] mtime_o,
  output logic msip_o,
  output logic mtip_o,
  output logic meip_o,
  output logic seip_o,

  output logic eth_psel_o,
  output logic eth_penable_o,
  output logic eth_pwrite_o,
  output logic [AP_PADDR_W-1:0] eth_paddr_o,
  output logic [31:0] eth_pwdata_o,
  output logic [3:0] eth_pstrb_o,
  input logic eth_pready_i,
  input logic [31:0] eth_prdata_i,
  input logic eth_pslverr_i,

  AXI_BUS.Slave periph_axi_i,

  AXI_BUS.Master bpi_axi_o,

  output logic [AP_BPI_ADDR_W-1:0] bpi_addr_o,
  inout wire [AP_BPI_DATA_W-1:0] bpi_dq_io,
  output logic bpi_ce_n_o,
  output logic bpi_oe_n_o,
  output logic bpi_we_n_o,
  output logic bpi_adv_n_o,
  output logic bpi_reset_n_o,
  input logic bpi_ryby_n_i
);

  logic apb_psel;
  logic apb_penable;
  logic apb_pwrite;
  logic [AP_PADDR_W-1:0] apb_paddr;
  logic [31:0] apb_pwdata;
  logic [3:0] apb_pstrb;
  logic apb_pready;
  logic [31:0] apb_prdata;
  logic apb_pslverr;

  logic clint_psel;
  logic clint_pready;
  logic [31:0] clint_prdata;
  logic clint_pslverr;
  logic plic_psel;
  logic plic_pready;
  logic [31:0] plic_prdata;
  logic plic_pslverr;
  logic uart_psel;
  logic uart_pready;
  logic [31:0] uart_prdata;
  logic uart_pslverr;
  logic uart_irq;
  logic uart_busy;
  logic spi_psel;
  logic spi_pready;
  logic [31:0] spi_prdata;
  logic spi_pslverr;
  logic spi_irq;
  logic spi_busy;
  logic timer_psel;
  logic timer_pready;
  logic [31:0] timer_prdata;
  logic timer_pslverr;
  logic timer_irq;
  logic timer_busy;
  logic gpio_psel;
  logic gpio_pready;
  logic [31:0] gpio_prdata;
  logic gpio_pslverr;
  logic eth_psel;
  logic [31:0] plic_src;

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) periph_egress [AP_AXI_PERIPH_EGRESS_PORTS-1:0] ();

  ap_axi_periph_xbar periph_xbar_i (
    .clk_i(clk),
    .rst_ni(rst_n),
    .slv_axi_i(periph_axi_i),
    .mst_axi_o(periph_egress)
  );

  generate
    if (USE_EMBEDDED_BPI_NOR_P) begin : g_embedded_bpi
      ap_axi_bpi_nor #(
        .READ_WAIT_CYCLES_P(BPI_READ_WAIT_CYCLES_P),
        .ADV_PULSE_CYCLES_P(BPI_ADV_PULSE_CYCLES_P)
      ) bpi_nor_i (
        .clk(clk),
        .rst_n(rst_n),
        .s_axi_i(periph_egress[AP_AXI_PERIPH_EGRESS_FLASH]),
        .bpi_addr_o(bpi_addr_o),
        .bpi_dq_io(bpi_dq_io),
        .bpi_ce_n_o(bpi_ce_n_o),
        .bpi_oe_n_o(bpi_oe_n_o),
        .bpi_we_n_o(bpi_we_n_o),
        .bpi_adv_n_o(bpi_adv_n_o),
        .bpi_reset_n_o(bpi_reset_n_o),
        .bpi_ryby_n_i(bpi_ryby_n_i)
      );
      ap_axi64_idle_master bpi_idle_i (
        .m_axi_o(bpi_axi_o)
      );
    end else begin : g_external_bpi
      `AXI_ASSIGN(bpi_axi_o, periph_egress[AP_AXI_PERIPH_EGRESS_FLASH])
      assign bpi_addr_o = '0;
      assign bpi_dq_io = {AP_BPI_DATA_W{1'bz}};
      assign bpi_ce_n_o = 1'b1;
      assign bpi_oe_n_o = 1'b1;
      assign bpi_we_n_o = 1'b1;
      assign bpi_adv_n_o = 1'b1;
      assign bpi_reset_n_o = rst_n;
    end
  endgenerate;

  ap_axi64_to_apb32 axi_to_apb_i (
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_i(periph_egress[AP_AXI_PERIPH_EGRESS_APB]),
    .apb_psel_o(apb_psel),
    .apb_penable_o(apb_penable),
    .apb_pwrite_o(apb_pwrite),
    .apb_paddr_o(apb_paddr),
    .apb_pwdata_o(apb_pwdata),
    .apb_pstrb_o(apb_pstrb),
    .apb_pready_i(apb_pready),
    .apb_prdata_i(apb_prdata),
    .apb_pslverr_i(apb_pslverr)
  );

  clint #(
    .BASE_ADDR(AP_CLINT_BASE[31:0])
  ) clint_i (
    .clk(clk),
    .rst_n(rst_n),
    .psel_i(clint_psel),
    .penable_i(apb_penable),
    .pwrite_i(apb_pwrite),
    .paddr_i(apb_paddr[31:0]),
    .pwdata_i(apb_pwdata),
    .pstrb_i(apb_pstrb),
    .pready_o(clint_pready),
    .prdata_o(clint_prdata),
    .pslverr_o(clint_pslverr),
    .msip_o(msip_o),
    .mtip_o(mtip_o),
    .mtime_o(mtime_o)
  );

  always_comb begin
    plic_src = '0;
    plic_src[0] = uart_irq;
    plic_src[1] = spi_irq;
    plic_src[2] = timer_irq;
    plic_src[4] = eth_irq_i;
  end

  plic plic_i (
    .clk(clk),
    .rst_n(rst_n),
    .psel_i(plic_psel),
    .penable_i(apb_penable),
    .pwrite_i(apb_pwrite),
    .paddr_i(apb_paddr[31:0]),
    .pwdata_i(apb_pwdata),
    .pstrb_i(apb_pstrb),
    .pready_o(plic_pready),
    .prdata_o(plic_prdata),
    .pslverr_o(plic_pslverr),
    .src_i(plic_src),
    .meip_o(meip_o),
    .seip_o(seip_o)
  );

  assign eth_penable_o = apb_penable;
  assign eth_pwrite_o = apb_pwrite;
  assign eth_paddr_o = apb_paddr;
  assign eth_pwdata_o = apb_pwdata;
  assign eth_pstrb_o = apb_pstrb;

  ap_apb_interconnect apb_interconnect_i (
    .psel_i(apb_psel),
    .penable_i(apb_penable),
    .paddr_i(apb_paddr),
    .clint_psel_o(clint_psel),
    .clint_pready_i(clint_pready),
    .clint_prdata_i(clint_prdata),
    .clint_pslverr_i(clint_pslverr),
    .plic_psel_o(plic_psel),
    .plic_pready_i(plic_pready),
    .plic_prdata_i(plic_prdata),
    .plic_pslverr_i(plic_pslverr),
    .uart_psel_o(uart_psel),
    .uart_pready_i(uart_pready),
    .uart_prdata_i(uart_prdata),
    .uart_pslverr_i(uart_pslverr),
    .spi_psel_o(spi_psel),
    .spi_pready_i(spi_pready),
    .spi_prdata_i(spi_prdata),
    .spi_pslverr_i(spi_pslverr),
    .timer_psel_o(timer_psel),
    .timer_pready_i(timer_pready),
    .timer_prdata_i(timer_prdata),
    .timer_pslverr_i(timer_pslverr),
    .gpio_psel_o(gpio_psel),
    .gpio_pready_i(gpio_pready),
    .gpio_prdata_i(gpio_prdata),
    .gpio_pslverr_i(gpio_pslverr),
    .eth_psel_o(eth_psel),
    .eth_pready_i(eth_pready_i),
    .eth_prdata_i(eth_prdata_i),
    .eth_pslverr_i(eth_pslverr_i),
    .pready_o(apb_pready),
    .prdata_o(apb_prdata),
    .pslverr_o(apb_pslverr)
  );

  assign eth_psel_o = eth_psel;

  uart_apb uart0_i (
    .pclk(clk),
    .presetn(rst_n),
    .psel_i(uart_psel),
    .penable_i(apb_penable),
    .pwrite_i(apb_pwrite),
    .paddr_i(apb_paddr[31:0]),
    .pwdata_i(apb_pwdata),
    .pstrb_i(apb_pstrb),
    .pready_o(uart_pready),
    .prdata_o(uart_prdata),
    .pslverr_o(uart_pslverr),
    .dma_tx_valid_i(1'b0),
    .dma_tx_data_i('0),
    .dma_tx_ready_o(),
    .uart_rx_i(uart_rx_i),
    .uart_tx_o(uart_tx_o),
    .irq_o(uart_irq),
    .busy_o(uart_busy)
  );

  spi_apb spi0_i (
    .pclk(clk),
    .presetn(rst_n),
    .psel_i(spi_psel),
    .penable_i(apb_penable),
    .pwrite_i(apb_pwrite),
    .paddr_i(apb_paddr[31:0]),
    .pwdata_i(apb_pwdata),
    .pstrb_i(apb_pstrb),
    .pready_o(spi_pready),
    .prdata_o(spi_prdata),
    .pslverr_o(spi_pslverr),
    .spi_sclk_o(spi_sclk_o),
    .spi_mosi_o(spi_mosi_o),
    .spi_miso_i(spi_miso_i),
    .spi_ss_o(spi_ss_o),
    .irq_o(spi_irq),
    .busy_o(spi_busy)
  );

  timer_apb timer0_i (
    .pclk(clk),
    .presetn(rst_n),
    .psel_i(timer_psel),
    .penable_i(apb_penable),
    .pwrite_i(apb_pwrite),
    .paddr_i(apb_paddr[31:0]),
    .pwdata_i(apb_pwdata),
    .pstrb_i(apb_pstrb),
    .pready_o(timer_pready),
    .prdata_o(timer_prdata),
    .pslverr_o(timer_pslverr),
    .irq_o(timer_irq),
    .busy_o(timer_busy)
  );

  gpio_apb gpio0_i (
    .pclk(clk),
    .presetn(rst_n),
    .psel_i(gpio_psel),
    .penable_i(apb_penable),
    .pwrite_i(apb_pwrite),
    .paddr_i(apb_paddr[31:0]),
    .pwdata_i(apb_pwdata),
    .pstrb_i(apb_pstrb),
    .pready_o(gpio_pready),
    .prdata_o(gpio_prdata),
    .pslverr_o(gpio_pslverr),
    .gpio_i(gpio_i),
    .gpio_o(gpio_o),
    .gpio_oe_o(gpio_oe_o)
  );

endmodule
