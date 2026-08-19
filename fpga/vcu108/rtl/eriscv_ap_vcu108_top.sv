// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// eRISCV-AP VCU108 implementation top.  The AP SoC runs from the 50 MHz
// auxiliary MIG UI clock; the 300 MHz MIG UI clock remains the raw DDR AXI domain.
// The BPI NOR is a board service: the AP exposes an AXI target and this top
// crosses it to the VCU108 AXI EMC/STARTUPE3 implementation.
module eriscv_ap_vcu108_top
  import ap_soc_pkg::*;
(
  // Board clock and console.
  input wire sys_clk_p,
  input wire sys_clk_n,
  input wire cpu_reset_i,
  input wire uart_rx_i,
  output wire uart_tx_o,
  output wire [4:0] led_o,

  // VCU108 C1 DDR4.
  output wire [16:0] c0_ddr4_adr,
  output wire [1:0] c0_ddr4_ba,
  output wire [0:0] c0_ddr4_cke,
  output wire [0:0] c0_ddr4_cs_n,
  inout wire [7:0] c0_ddr4_dm_dbi_n,
  inout wire [63:0] c0_ddr4_dq,
  inout wire [7:0] c0_ddr4_dqs_c,
  inout wire [7:0] c0_ddr4_dqs_t,
  output wire [0:0] c0_ddr4_odt,
  output wire [0:0] c0_ddr4_bg,
  output wire c0_ddr4_reset_n,
  output wire c0_ddr4_act_n,
  output wire [0:0] c0_ddr4_ck_c,
  output wire [0:0] c0_ddr4_ck_t,

  // M88E1111 SGMII PHY.
  input wire phy_sgmii_rx_p,
  input wire phy_sgmii_rx_n,
  output wire phy_sgmii_tx_p,
  output wire phy_sgmii_tx_n,
  input wire phy_sgmii_clk_p,
  input wire phy_sgmii_clk_n,
  output wire phy_reset_n_o,
  input wire phy_int_n_i,

  // Dedicated BPI x16 NOR pins. D[3:0], CE#, and CCLK use STARTUPE3.
  output wire [25:0] bpi_addr_o,
  inout wire [15:4] bpi_dq_upper_io,
  output wire bpi_oe_n_o,
  output wire bpi_we_n_o,
  output wire bpi_adv_n_o,
  input wire bpi_ryby_n_i
);

  logic sys_clk_ibuf;
  logic sys_clk;
  logic soc_clk;
  logic mig_calib_done;
  logic mig_ui_clk;
  logic mig_ui_clk_sync_rst;
  logic soc_rst_n;
  logic mig_axi_rst_n;
  logic fetch_enable;
  logic [2:0] soc_rst_sync_q;
  logic [1:0] fetch_enable_sync_q;

  logic bpi_axi_clk_mmcm;
  logic bpi_axi_clk;
  logic bpi_rdclk_mmcm;
  logic bpi_rdclk;
  logic bpi_clk_fb;
  logic bpi_clk_fb_buf;
  logic bpi_clk_locked;
  logic bpi_rst_n;
  logic [2:0] bpi_rst_sync_q;

  logic [31:0] gpio_o;
  logic [31:0] gpio_oe_o;
  logic spi_sclk;
  logic spi_mosi;
  logic [3:0] spi_ss;
  logic [7:0] eth_gmii_rxd;
  logic eth_gmii_rx_dv;
  logic eth_gmii_rx_er;
  logic [7:0] eth_gmii_txd;
  logic eth_gmii_tx_en;
  logic eth_gmii_tx_er;
  logic eth_gmii_clk;
  logic eth_gmii_rst;
  logic eth_gmii_clk_enable;
  logic [15:0] pcs_status;
  logic [4:0] pcs_configuration;
  logic [15:0] pcs_an_adv;
  logic debug_halted;
  logic debug_running;
  logic [63:0] debug_pc;
  logic [2:0] debug_cause;

  logic [AP_BPI_ADDR_W-1:0] ignored_bpi_addr;
  wire [AP_BPI_DATA_W-1:0] ignored_bpi_dq;
  logic ignored_bpi_ce_n;
  logic ignored_bpi_oe_n;
  logic ignored_bpi_we_n;
  logic ignored_bpi_adv_n;
  logic ignored_bpi_reset_n;

  logic [15:0] emc_dq_i;
  logic [15:0] emc_dq_o;
  logic [15:0] emc_dq_t;
  logic [31:0] emc_addr;
  logic emc_cen;
  logic emc_oen;
  logic emc_wen;
  logic emc_adv_n;
  logic emc_rpn;
  logic emc_wait;

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) soc_ddr_axi ();
  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) ddr_axi ();
  AXI_BUS #(
    .AXI_ADDR_WIDTH(31),
    .AXI_DATA_WIDTH(512),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) mig_axi ();
  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) soc_bpi_axi ();
  AXI_BUS #(
    .AXI_ADDR_WIDTH(32),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) emc_axi ();

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

  // 300 MHz board reference -> 100 MHz AXI EMC and 50 MHz BPI read clock.
  MMCME3_BASE #(
    .BANDWIDTH("OPTIMIZED"),
    .CLKFBOUT_MULT_F(4.000),
    .CLKIN1_PERIOD(3.333),
    .CLKOUT0_DIVIDE_F(12.000),
    .CLKOUT1_DIVIDE(24),
    .DIVCLK_DIVIDE(1),
    .STARTUP_WAIT("FALSE")
  ) bpi_clock_mmcm_i (
    .CLKIN1(sys_clk),
    .CLKFBIN(bpi_clk_fb_buf),
    .RST(cpu_reset_i),
    .PWRDWN(1'b0),
    .CLKFBOUT(bpi_clk_fb),
    .CLKOUT0(bpi_axi_clk_mmcm),
    .CLKOUT1(bpi_rdclk_mmcm),
    .LOCKED(bpi_clk_locked),
    .CLKFBOUTB(),
    .CLKOUT0B(),
    .CLKOUT1B(),
    .CLKOUT2(),
    .CLKOUT2B(),
    .CLKOUT3(),
    .CLKOUT3B(),
    .CLKOUT4(),
    .CLKOUT5(),
    .CLKOUT6()
  );

  BUFG bpi_clk_fb_bufg_i (
    .I(bpi_clk_fb),
    .O(bpi_clk_fb_buf)
  );

  BUFG bpi_axi_clk_bufg_i (
    .I(bpi_axi_clk_mmcm),
    .O(bpi_axi_clk)
  );

  BUFG bpi_rdclk_bufg_i (
    .I(bpi_rdclk_mmcm),
    .O(bpi_rdclk)
  );

  always_ff @(posedge soc_clk or posedge mig_ui_clk_sync_rst) begin
    if (mig_ui_clk_sync_rst || !mig_calib_done) begin
      soc_rst_sync_q <= '0;
    end else begin
      soc_rst_sync_q <= {soc_rst_sync_q[1:0], 1'b1};
    end
  end
  assign soc_rst_n = soc_rst_sync_q[2];
  assign mig_axi_rst_n = !mig_ui_clk_sync_rst && mig_calib_done;

  always_ff @(posedge soc_clk or negedge soc_rst_n) begin
    if (!soc_rst_n) begin
      fetch_enable_sync_q <= '0;
    end else begin
      fetch_enable_sync_q <= {fetch_enable_sync_q[0], 1'b1};
    end
  end
  assign fetch_enable = fetch_enable_sync_q[1];

  always_ff @(posedge bpi_axi_clk or negedge bpi_clk_locked) begin
    if (!bpi_clk_locked) begin
      bpi_rst_sync_q <= '0;
    end else if (!soc_rst_n) begin
      bpi_rst_sync_q <= '0;
    end else begin
      bpi_rst_sync_q <= {bpi_rst_sync_q[1:0], 1'b1};
    end
  end
  assign bpi_rst_n = bpi_rst_sync_q[2];

  ap_soc #(
    .USE_EMBEDDED_BPI_NOR_P(1'b0)
  ) soc_i (
    .clk(soc_clk),
    .rst_n(soc_rst_n),
    .fetch_enable_i(fetch_enable),
    .mtime_i('0),
    .irq_i('0),
    .uart_rx_i(uart_rx_i),
    .uart_tx_o(uart_tx_o),
    .gpio_i('0),
    .gpio_o(gpio_o),
    .gpio_oe_o(gpio_oe_o),
    .spi_miso_i(1'b0),
    .spi_sclk_o(spi_sclk),
    .spi_mosi_o(spi_mosi),
    .spi_ss_o(spi_ss),
    .eth_rx_clk_i(eth_gmii_clk),
    .eth_rx_rst_n_i(!eth_gmii_rst),
    .eth_gmii_rxd_i(eth_gmii_rxd),
    .eth_gmii_rx_dv_i(eth_gmii_rx_dv),
    .eth_gmii_rx_er_i(eth_gmii_rx_er),
    .eth_tx_clk_i(eth_gmii_clk),
    .eth_tx_rst_n_i(!eth_gmii_rst),
    .eth_gmii_clk_enable_i(eth_gmii_clk_enable),
    .eth_gmii_txd_o(eth_gmii_txd),
    .eth_gmii_tx_en_o(eth_gmii_tx_en),
    .eth_gmii_tx_er_o(eth_gmii_tx_er),
    .debug_halt_req_i(1'b0),
    .debug_resume_req_i(1'b0),
    .debug_halted_o(debug_halted),
    .debug_running_o(debug_running),
    .debug_pc_o(debug_pc),
    .debug_cause_o(debug_cause),
    .ddr_axi_o(soc_ddr_axi),
    .bpi_axi_o(soc_bpi_axi),
    .bpi_addr_o(ignored_bpi_addr),
    .bpi_dq_io(ignored_bpi_dq),
    .bpi_ce_n_o(ignored_bpi_ce_n),
    .bpi_oe_n_o(ignored_bpi_oe_n),
    .bpi_we_n_o(ignored_bpi_we_n),
    .bpi_adv_n_o(ignored_bpi_adv_n),
    .bpi_reset_n_o(ignored_bpi_reset_n),
    .bpi_ryby_n_i(1'b1)
  );

  // The AP SoC runs at 50 MHz; its 64-bit AXI port crosses into the 300 MHz
  // MIG UI domain before address translation and width conversion.
  axi_cdc_intf #(
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W),
    .LOG_DEPTH(2)
  ) ddr_cdc_i (
    .src_clk_i(soc_clk),
    .src_rst_ni(soc_rst_n),
    .src(soc_ddr_axi),
    .dst_clk_i(mig_ui_clk),
    .dst_rst_ni(mig_axi_rst_n),
    .dst(ddr_axi)
  );

  ap_axi_ddr_bridge ddr_bridge_i (
    .clk_i(mig_ui_clk),
    .rst_ni(mig_axi_rst_n),
    .ap_axi_i(ddr_axi),
    .mig_axi_o(mig_axi)
  );

  ap_axi_bpi_bridge bpi_bridge_i (
    .src_clk_i(soc_clk),
    .src_rst_ni(soc_rst_n),
    .ap_axi_i(soc_bpi_axi),
    .emc_clk_i(bpi_axi_clk),
    .emc_rst_ni(bpi_rst_n),
    .emc_axi_o(emc_axi)
  );

  axi_emc_bpi bpi_emc_i (
    .s_axi_aclk(bpi_axi_clk),
    .s_axi_aresetn(bpi_rst_n),
    .rdclk(bpi_rdclk),
    .s_axi_mem_awid(emc_axi.aw_id),
    .s_axi_mem_awaddr(emc_axi.aw_addr),
    .s_axi_mem_awlen(emc_axi.aw_len),
    .s_axi_mem_awsize(emc_axi.aw_size),
    .s_axi_mem_awburst(emc_axi.aw_burst),
    .s_axi_mem_awlock(emc_axi.aw_lock),
    .s_axi_mem_awcache(emc_axi.aw_cache),
    .s_axi_mem_awprot(emc_axi.aw_prot),
    .s_axi_mem_awvalid(emc_axi.aw_valid),
    .s_axi_mem_awready(emc_axi.aw_ready),
    .s_axi_mem_wdata(emc_axi.w_data),
    .s_axi_mem_wstrb(emc_axi.w_strb),
    .s_axi_mem_wlast(emc_axi.w_last),
    .s_axi_mem_wvalid(emc_axi.w_valid),
    .s_axi_mem_wready(emc_axi.w_ready),
    .s_axi_mem_bid(emc_axi.b_id),
    .s_axi_mem_bresp(emc_axi.b_resp),
    .s_axi_mem_bvalid(emc_axi.b_valid),
    .s_axi_mem_bready(emc_axi.b_ready),
    .s_axi_mem_arid(emc_axi.ar_id),
    .s_axi_mem_araddr(emc_axi.ar_addr),
    .s_axi_mem_arlen(emc_axi.ar_len),
    .s_axi_mem_arsize(emc_axi.ar_size),
    .s_axi_mem_arburst(emc_axi.ar_burst),
    .s_axi_mem_arlock(emc_axi.ar_lock),
    .s_axi_mem_arcache(emc_axi.ar_cache),
    .s_axi_mem_arprot(emc_axi.ar_prot),
    .s_axi_mem_arvalid(emc_axi.ar_valid),
    .s_axi_mem_arready(emc_axi.ar_ready),
    .s_axi_mem_rid(emc_axi.r_id),
    .s_axi_mem_rdata(emc_axi.r_data),
    .s_axi_mem_rresp(emc_axi.r_resp),
    .s_axi_mem_rlast(emc_axi.r_last),
    .s_axi_mem_rvalid(emc_axi.r_valid),
    .s_axi_mem_rready(emc_axi.r_ready),
    .mem_dq_i(emc_dq_i),
    .mem_dq_o(emc_dq_o),
    .mem_dq_t(emc_dq_t),
    .mem_a(emc_addr),
    .mem_ce(),
    .mem_cen(emc_cen),
    .mem_oen(emc_oen),
    .mem_wen(emc_wen),
    .mem_ben(),
    .mem_qwen(),
    .mem_rpn(emc_rpn),
    .mem_adv_ldn(emc_adv_n),
    .mem_lbon(),
    .mem_cken(),
    .mem_rnw(),
    .mem_cre(),
    .mem_wait(emc_wait)
  );

  assign emc_axi.b_user = '0;
  assign emc_axi.r_user = '0;

  ap_vcu108_bpi_io bpi_io_i (
    .bpi_clk_i(bpi_rdclk),
    .mem_dq_o_i(emc_dq_o),
    .mem_dq_t_i(emc_dq_t),
    .mem_dq_i_o(emc_dq_i),
    .mem_ce_n_i(emc_cen),
    .mem_addr_i(emc_addr[25:0]),
    .mem_oe_n_i(emc_oen),
    .mem_we_n_i(emc_wen),
    .mem_adv_n_i(emc_adv_n),
    .mem_reset_n_i(1'b1),
    .mem_wait_i(emc_wait),
    .bpi_addr_o(bpi_addr_o),
    .bpi_dq_upper_io(bpi_dq_upper_io),
    .bpi_oe_n_o(bpi_oe_n_o),
    .bpi_we_n_o(bpi_we_n_o),
    .bpi_adv_n_o(bpi_adv_n_o),
    .bpi_reset_n_o(),
    .bpi_ryby_n_i(bpi_ryby_n_i)
  );

  assign pcs_configuration = 5'b10000;
  assign pcs_an_adv = 16'h0001;
  gig_ethernet_pcs_pma_0 pcs_pma_i (
    .txp(phy_sgmii_tx_p),
    .txn(phy_sgmii_tx_n),
    .rxp(phy_sgmii_rx_p),
    .rxn(phy_sgmii_rx_n),
    .refclk625_p(phy_sgmii_clk_p),
    .refclk625_n(phy_sgmii_clk_n),
    .reset(!soc_rst_n),
    .clk125_out(eth_gmii_clk),
    .clk625_out(),
    .clk312_out(),
    .rst_125_out(eth_gmii_rst),
    .idelay_rdy_out(),
    .mmcm_locked_out(),
    .sgmii_clk_r(),
    .sgmii_clk_f(),
    .sgmii_clk_en(eth_gmii_clk_enable),
    .speed_is_10_100(pcs_status[11:10] != 2'b10),
    .speed_is_100(pcs_status[11:10] == 2'b01),
    .gmii_txd(eth_gmii_txd),
    .gmii_tx_en(eth_gmii_tx_en),
    .gmii_tx_er(eth_gmii_tx_er),
    .gmii_rxd(eth_gmii_rxd),
    .gmii_rx_dv(eth_gmii_rx_dv),
    .gmii_rx_er(eth_gmii_rx_er),
    .gmii_isolate(),
    .configuration_vector(pcs_configuration),
    .an_interrupt(),
    .an_adv_config_vector(pcs_an_adv),
    .an_restart_config(1'b0),
    .status_vector(pcs_status),
    .signal_detect(1'b1)
  );

  mig_ddr4_0 mig_i (
    .c0_init_calib_complete(mig_calib_done),
    .dbg_clk(),
    .c0_sys_clk_i(sys_clk),
    .dbg_bus(),
    .c0_ddr4_adr(c0_ddr4_adr),
    .c0_ddr4_ba(c0_ddr4_ba),
    .c0_ddr4_cke(c0_ddr4_cke),
    .c0_ddr4_cs_n(c0_ddr4_cs_n),
    .c0_ddr4_dm_dbi_n(c0_ddr4_dm_dbi_n),
    .c0_ddr4_dq(c0_ddr4_dq),
    .c0_ddr4_dqs_c(c0_ddr4_dqs_c),
    .c0_ddr4_dqs_t(c0_ddr4_dqs_t),
    .c0_ddr4_odt(c0_ddr4_odt),
    .c0_ddr4_bg(c0_ddr4_bg),
    .c0_ddr4_reset_n(c0_ddr4_reset_n),
    .c0_ddr4_act_n(c0_ddr4_act_n),
    .c0_ddr4_ck_c(c0_ddr4_ck_c),
    .c0_ddr4_ck_t(c0_ddr4_ck_t),
    .c0_ddr4_ui_clk(mig_ui_clk),
    .c0_ddr4_ui_clk_sync_rst(mig_ui_clk_sync_rst),
    .c0_ddr4_aresetn(!cpu_reset_i),
    .c0_ddr4_s_axi_awid(mig_axi.aw_id),
    .c0_ddr4_s_axi_awaddr(mig_axi.aw_addr),
    .c0_ddr4_s_axi_awlen(mig_axi.aw_len),
    .c0_ddr4_s_axi_awsize(mig_axi.aw_size),
    .c0_ddr4_s_axi_awburst(mig_axi.aw_burst),
    .c0_ddr4_s_axi_awlock(mig_axi.aw_lock),
    .c0_ddr4_s_axi_awcache(mig_axi.aw_cache),
    .c0_ddr4_s_axi_awprot(mig_axi.aw_prot),
    .c0_ddr4_s_axi_awqos(mig_axi.aw_qos),
    .c0_ddr4_s_axi_awvalid(mig_axi.aw_valid),
    .c0_ddr4_s_axi_awready(mig_axi.aw_ready),
    .c0_ddr4_s_axi_wdata(mig_axi.w_data),
    .c0_ddr4_s_axi_wstrb(mig_axi.w_strb),
    .c0_ddr4_s_axi_wlast(mig_axi.w_last),
    .c0_ddr4_s_axi_wvalid(mig_axi.w_valid),
    .c0_ddr4_s_axi_wready(mig_axi.w_ready),
    .c0_ddr4_s_axi_bready(mig_axi.b_ready),
    .c0_ddr4_s_axi_bid(mig_axi.b_id),
    .c0_ddr4_s_axi_bresp(mig_axi.b_resp),
    .c0_ddr4_s_axi_bvalid(mig_axi.b_valid),
    .c0_ddr4_s_axi_arid(mig_axi.ar_id),
    .c0_ddr4_s_axi_araddr(mig_axi.ar_addr),
    .c0_ddr4_s_axi_arlen(mig_axi.ar_len),
    .c0_ddr4_s_axi_arsize(mig_axi.ar_size),
    .c0_ddr4_s_axi_arburst(mig_axi.ar_burst),
    .c0_ddr4_s_axi_arlock(mig_axi.ar_lock),
    .c0_ddr4_s_axi_arcache(mig_axi.ar_cache),
    .c0_ddr4_s_axi_arprot(mig_axi.ar_prot),
    .c0_ddr4_s_axi_arqos(mig_axi.ar_qos),
    .c0_ddr4_s_axi_arvalid(mig_axi.ar_valid),
    .c0_ddr4_s_axi_arready(mig_axi.ar_ready),
    .c0_ddr4_s_axi_rready(mig_axi.r_ready),
    .c0_ddr4_s_axi_rlast(mig_axi.r_last),
    .c0_ddr4_s_axi_rvalid(mig_axi.r_valid),
    .c0_ddr4_s_axi_rresp(mig_axi.r_resp),
    .c0_ddr4_s_axi_rid(mig_axi.r_id),
    .c0_ddr4_s_axi_rdata(mig_axi.r_data),
    .addn_ui_clkout1(soc_clk),
    .sys_rst(cpu_reset_i)
  );

  assign mig_axi.b_user = '0;
  assign mig_axi.r_user = '0;
  assign phy_reset_n_o = soc_rst_n;
  assign led_o[0] = mig_calib_done;
  assign led_o[1] = soc_rst_n;
  assign led_o[2] = debug_running;
  assign led_o[3] = !phy_int_n_i;
  assign led_o[4] = eth_gmii_rst;

endmodule
