// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// AP uncached-device subsystem.  Local CLINT/PLIC/APB devices terminate on a
// 64-bit AXI slave; only the non-overlapping BPI aperture reaches the external
// peripheral AXI egress.  Interrupt signals bypass APB and feed the hart
// directly through soc.sv.
module ap_peripheral_subsystem
  import ap_soc_pkg::*;
(
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

  AXI_BUS.Slave periph_axi_i,
  AXI_BUS.Master periph_axi_o
);

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) local_axi ();

  logic dbus_req_valid;
  logic dbus_req_ready;
  logic dbus_we;
  logic [AP_PADDR_W-1:0] dbus_addr;
  logic [31:0] dbus_wdata;
  logic [3:0] dbus_be;
  logic dbus_resp_valid;
  logic [31:0] dbus_rdata;
  logic dbus_err;

  ap_axi64_peripheral_router peripheral_router_i (
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_i(periph_axi_i),
    .local_axi_o(local_axi),
    .bpi_axi_o(periph_axi_o)
  );

  ap_axi64_to_dbus32 axi_to_dbus_i (
    .clk(clk),
    .rst_n(rst_n),
    .s_axi_i(local_axi),
    .dbus_req_valid_o(dbus_req_valid),
    .dbus_req_ready_i(dbus_req_ready),
    .dbus_we_o(dbus_we),
    .dbus_addr_o(dbus_addr),
    .dbus_wdata_o(dbus_wdata),
    .dbus_be_o(dbus_be),
    .dbus_resp_valid_i(dbus_resp_valid),
    .dbus_rdata_i(dbus_rdata),
    .dbus_err_i(dbus_err)
  );

  typedef enum logic [2:0] {
    DBUS_IDLE,
    DBUS_DISPATCH,
    DBUS_CLINT_READ,
    DBUS_PLIC_READ,
    DBUS_APB_SETUP,
    DBUS_APB_ACCESS,
    DBUS_RESP
  } dbus_state_e;

  dbus_state_e dbus_state_q;
  logic dbus_we_q;
  logic [AP_PADDR_W-1:0] dbus_addr_q;
  logic [31:0] dbus_wdata_q;
  logic [3:0] dbus_be_q;
  logic [31:0] dbus_rdata_q;
  logic dbus_err_q;

  logic clint_req;
  logic clint_hit;
  logic clint_write_accept;
  logic clint_resp_valid;
  logic [31:0] clint_rdata;
  logic clint_err;
  logic plic_req;
  logic plic_hit;
  logic plic_write_accept;
  logic plic_resp_valid;
  logic [31:0] plic_rdata;
  logic plic_err;
  logic apb_psel;
  logic apb_penable;
  logic apb_pready;
  logic [31:0] apb_prdata;
  logic apb_pslverr;

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
  logic [31:0] plic_src;

  assign dbus_req_ready = dbus_state_q == DBUS_IDLE;
  assign dbus_resp_valid = dbus_state_q == DBUS_RESP;
  assign dbus_rdata = dbus_rdata_q;
  assign dbus_err = dbus_err_q;
  assign clint_req = (dbus_state_q == DBUS_DISPATCH) &&
                     ap_addr_in_range(dbus_addr_q, AP_CLINT_BASE, AP_CLINT_LIMIT);
  assign plic_req = (dbus_state_q == DBUS_DISPATCH) &&
                    ap_addr_in_range(dbus_addr_q, AP_PLIC_BASE, AP_PLIC_LIMIT);
  assign apb_psel = (dbus_state_q == DBUS_APB_SETUP) ||
                    (dbus_state_q == DBUS_APB_ACCESS);
  assign apb_penable = dbus_state_q == DBUS_APB_ACCESS;

  clint #(
    .BASE_ADDR(AP_CLINT_BASE[31:0])
  ) clint_i (
    .clk(clk),
    .rst_n(rst_n),
    .req_i(clint_req),
    .we_i(dbus_we_q),
    .be_i(dbus_be_q),
    .addr_i(dbus_addr_q[31:0]),
    .wdata_i(dbus_wdata_q),
    .hit_o(clint_hit),
    .write_accept_o(clint_write_accept),
    .resp_valid_o(clint_resp_valid),
    .rdata_o(clint_rdata),
    .err_o(clint_err),
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
    .req_i(plic_req),
    .we_i(dbus_we_q),
    .be_i(dbus_be_q),
    .addr_i(dbus_addr_q[31:0]),
    .wdata_i(dbus_wdata_q),
    .hit_o(plic_hit),
    .write_accept_o(plic_write_accept),
    .resp_valid_o(plic_resp_valid),
    .rdata_o(plic_rdata),
    .err_o(plic_err),
    .src_i(plic_src),
    .meip_o(meip_o),
    .seip_o(seip_o)
  );

  ap_apb_interconnect apb_interconnect_i (
    .psel_i(apb_psel),
    .penable_i(apb_penable),
    .paddr_i(dbus_addr_q),
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
    .pready_o(apb_pready),
    .prdata_o(apb_prdata),
    .pslverr_o(apb_pslverr)
  );

  uart_apb uart0_i (
    .pclk(clk),
    .presetn(rst_n),
    .psel_i(uart_psel),
    .penable_i(apb_penable),
    .pwrite_i(dbus_we_q),
    .paddr_i(dbus_addr_q[31:0]),
    .pwdata_i(dbus_wdata_q),
    .pstrb_i(dbus_be_q),
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
    .pwrite_i(dbus_we_q),
    .paddr_i(dbus_addr_q[31:0]),
    .pwdata_i(dbus_wdata_q),
    .pstrb_i(dbus_be_q),
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
    .pwrite_i(dbus_we_q),
    .paddr_i(dbus_addr_q[31:0]),
    .pwdata_i(dbus_wdata_q),
    .pstrb_i(dbus_be_q),
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
    .pwrite_i(dbus_we_q),
    .paddr_i(dbus_addr_q[31:0]),
    .pwdata_i(dbus_wdata_q),
    .pstrb_i(dbus_be_q),
    .pready_o(gpio_pready),
    .prdata_o(gpio_prdata),
    .pslverr_o(gpio_pslverr),
    .gpio_i(gpio_i),
    .gpio_o(gpio_o),
    .gpio_oe_o(gpio_oe_o)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dbus_state_q <= DBUS_IDLE;
      dbus_we_q <= 1'b0;
      dbus_addr_q <= '0;
      dbus_wdata_q <= '0;
      dbus_be_q <= '0;
      dbus_rdata_q <= '0;
      dbus_err_q <= 1'b0;
    end else begin
      unique case (dbus_state_q)
        DBUS_IDLE: begin
          if (dbus_req_valid) begin
            dbus_we_q <= dbus_we;
            dbus_addr_q <= dbus_addr;
            dbus_wdata_q <= dbus_wdata;
            dbus_be_q <= dbus_be;
            dbus_err_q <= 1'b0;
            dbus_state_q <= DBUS_DISPATCH;
          end
        end
        DBUS_DISPATCH: begin
          if (ap_addr_in_range(dbus_addr_q, AP_CLINT_BASE, AP_CLINT_LIMIT)) begin
            if (dbus_we_q) begin
              dbus_err_q <= !clint_write_accept;
              dbus_state_q <= DBUS_RESP;
            end else if (clint_hit) begin
              dbus_state_q <= DBUS_CLINT_READ;
            end else begin
              dbus_err_q <= 1'b1;
              dbus_state_q <= DBUS_RESP;
            end
          end else if (ap_addr_in_range(dbus_addr_q, AP_PLIC_BASE, AP_PLIC_LIMIT)) begin
            if (dbus_we_q) begin
              dbus_err_q <= !plic_write_accept;
              dbus_state_q <= DBUS_RESP;
            end else if (plic_hit) begin
              dbus_state_q <= DBUS_PLIC_READ;
            end else begin
              dbus_err_q <= 1'b1;
              dbus_state_q <= DBUS_RESP;
            end
          end else if (ap_addr_in_range(dbus_addr_q, AP_APB_BASE, AP_APB_LIMIT)) begin
            dbus_state_q <= DBUS_APB_SETUP;
          end else begin
            dbus_err_q <= 1'b1;
            dbus_state_q <= DBUS_RESP;
          end
        end
        DBUS_CLINT_READ: begin
          if (clint_resp_valid) begin
            dbus_rdata_q <= clint_rdata;
            dbus_err_q <= clint_err;
            dbus_state_q <= DBUS_RESP;
          end
        end
        DBUS_PLIC_READ: begin
          if (plic_resp_valid) begin
            dbus_rdata_q <= plic_rdata;
            dbus_err_q <= plic_err;
            dbus_state_q <= DBUS_RESP;
          end
        end
        DBUS_APB_SETUP: dbus_state_q <= DBUS_APB_ACCESS;
        DBUS_APB_ACCESS: begin
          if (apb_pready) begin
            dbus_rdata_q <= apb_prdata;
            dbus_err_q <= apb_pslverr;
            dbus_state_q <= DBUS_RESP;
          end
        end
        DBUS_RESP: dbus_state_q <= DBUS_IDLE;
        default: dbus_state_q <= DBUS_IDLE;
      endcase
    end
  end

endmodule
