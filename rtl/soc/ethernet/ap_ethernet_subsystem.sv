// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Ethernet subsystem boundary: APB control, posted RX/TX buffer policy,
// 64-bit AXI4 DMA, PHY-clock CDC, and a GMII 1G MAC.  The descriptor interface
// is intentionally one-buffer-at-a-time for bring-up; Linux descriptor rings
// are a later control-plane layer, not an alternate AXI data path.
module ap_ethernet_subsystem
  import ap_soc_pkg::*;
(
  input logic clk,
  input logic rst_n,

  input logic apb_psel_i,
  input logic apb_penable_i,
  input logic apb_pwrite_i,
  input logic [AP_PADDR_W-1:0] apb_paddr_i,
  input logic [31:0] apb_pwdata_i,
  input logic [3:0] apb_pstrb_i,
  output logic apb_pready_o,
  output logic [31:0] apb_prdata_o,
  output logic apb_pslverr_o,

  input logic eth_rx_clk_i,
  input logic eth_rx_rst_n_i,
  input logic [7:0] eth_gmii_rxd_i,
  input logic eth_gmii_rx_dv_i,
  input logic eth_gmii_rx_er_i,
  input logic eth_tx_clk_i,
  input logic eth_tx_rst_n_i,
  output logic [7:0] eth_gmii_txd_o,
  output logic eth_gmii_tx_en_o,
  output logic eth_gmii_tx_er_o,

  output logic irq_o,
  AXI_BUS.Master mem_axi_o
);

  localparam logic [15:0] RX_MAX_FRAME_BYTES = 16'd2048;
  localparam logic [15:0] TX_MAX_FRAME_BYTES = 16'd1536;

  logic tx_enable;
  logic rx_enable;
  logic [47:0] tx_addr;
  logic [15:0] tx_len;
  logic tx_start;
  logic tx_busy_q;
  logic tx_done_q;
  logic tx_error_q;
  logic tx_dma_ok_q;
  logic tx_last_byte_sent_q;
  logic tx_frame_ready_q;
  logic tx_frame_ready_cdc_ready;
  logic tx_frame_inflight_q;
  logic tx_frame_ready_phy_valid;
  logic tx_frame_consumed_phy;
  logic [47:0] rx_addr;
  logic [15:0] rx_capacity;
  logic rx_arm;
  logic rx_busy_q;
  logic rx_done_q;
  logic [15:0] rx_len_q;
  logic rx_error_q;

  logic tx_desc_valid_q;
  logic tx_desc_ready;
  logic [47:0] tx_desc_addr_q;
  logic [15:0] tx_desc_len_q;
  logic rx_desc_valid_q;
  logic rx_desc_ready;
  logic rx_desc_issued_q;
  logic [47:0] rx_desc_addr_q;
  logic [15:0] rx_desc_len_q;
  logic rx_buffer_arm_q;
  logic rx_buffer_start_q;
  logic rx_buffer_release_q;

  logic [63:0] dma_read_data;
  logic [7:0] dma_read_keep;
  logic dma_read_valid;
  logic dma_read_ready;
  logic dma_read_last;
  logic dma_read_user;
  logic [3:0] dma_read_status_error;
  logic dma_read_status_valid;
  logic [63:0] dma_write_data;
  logic [7:0] dma_write_keep;
  logic dma_write_valid;
  logic dma_write_ready;
  logic dma_write_last;
  logic [15:0] dma_write_status_len;
  logic [3:0] dma_write_status_error;
  logic dma_write_status_valid;

  logic [7:0] tx_byte_data;
  logic tx_byte_valid;
  logic tx_byte_ready;
  logic tx_byte_last;
  logic tx_byte_user;
  logic [7:0] tx_cdc_data;
  logic tx_cdc_valid;
  logic tx_cdc_last;
  logic tx_cdc_user;
  logic [7:0] mac_tx_data;
  logic mac_tx_valid;
  logic mac_tx_ready;
  logic mac_tx_last;
  logic mac_tx_user;
  logic [7:0] mac_rx_data;
  logic mac_rx_valid;
  logic mac_rx_last;
  logic mac_rx_user;
  logic mac_rx_ready;
  logic [7:0] rx_byte_data;
  logic rx_byte_valid;
  logic rx_byte_ready;
  logic rx_byte_last;
  logic rx_byte_user;
  logic rx_frame_ready;
  logic [15:0] rx_frame_len;
  logic rx_frame_drop;

  assign mac_tx_data = tx_cdc_data;
  assign mac_tx_valid = tx_frame_ready_phy_valid && tx_cdc_valid;
  assign mac_tx_last = tx_cdc_last;
  assign mac_tx_user = tx_cdc_user;
  assign tx_frame_consumed_phy = mac_tx_valid && mac_tx_ready && mac_tx_last;

  ap_eth_dma_regs regs_i (
    .pclk(clk),
    .presetn(rst_n),
    .psel_i(apb_psel_i),
    .penable_i(apb_penable_i),
    .pwrite_i(apb_pwrite_i),
    .paddr_i(apb_paddr_i[31:0]),
    .pwdata_i(apb_pwdata_i),
    .pstrb_i(apb_pstrb_i),
    .pready_o(apb_pready_o),
    .prdata_o(apb_prdata_o),
    .pslverr_o(apb_pslverr_o),
    .tx_enable_o(tx_enable),
    .rx_enable_o(rx_enable),
    .tx_addr_o(tx_addr),
    .tx_len_o(tx_len),
    .tx_start_o(tx_start),
    .tx_busy_i(tx_busy_q),
    .tx_done_i(tx_done_q),
    .tx_error_i(tx_error_q),
    .rx_addr_o(rx_addr),
    .rx_capacity_o(rx_capacity),
    .rx_arm_o(rx_arm),
    .rx_busy_i(rx_busy_q),
    .rx_done_i(rx_done_q),
    .rx_len_i(rx_len_q),
    .rx_error_i(rx_error_q),
    .irq_o(irq_o)
  );

  // Submit direct physical-buffer descriptors.  The last byte and DMA status
  // form a frame-complete token that crosses into the PHY clock domain.  This
  // delays GMII TX until the whole frame is buffered, preventing underflow when
  // the PHY clock is faster than the SoC root clock.  One frame is in flight.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_busy_q <= 1'b0;
      tx_done_q <= 1'b0;
      tx_error_q <= 1'b0;
      tx_dma_ok_q <= 1'b0;
      tx_last_byte_sent_q <= 1'b0;
      tx_frame_ready_q <= 1'b0;
      tx_frame_inflight_q <= 1'b0;
      tx_desc_valid_q <= 1'b0;
      tx_desc_addr_q <= '0;
      tx_desc_len_q <= '0;
      rx_busy_q <= 1'b0;
      rx_done_q <= 1'b0;
      rx_len_q <= '0;
      rx_error_q <= 1'b0;
      rx_desc_valid_q <= 1'b0;
      rx_desc_issued_q <= 1'b0;
      rx_desc_addr_q <= '0;
      rx_desc_len_q <= '0;
      rx_buffer_arm_q <= 1'b0;
      rx_buffer_start_q <= 1'b0;
      rx_buffer_release_q <= 1'b0;
    end else begin
      tx_done_q <= 1'b0;
      tx_error_q <= 1'b0;
      rx_done_q <= 1'b0;
      rx_error_q <= 1'b0;
      rx_buffer_arm_q <= 1'b0;
      rx_buffer_start_q <= 1'b0;
      rx_buffer_release_q <= 1'b0;

      if (tx_start) begin
        if ((tx_addr[2:0] != 3'b000) || (tx_len > TX_MAX_FRAME_BYTES) ||
            !tx_frame_ready_cdc_ready || tx_frame_ready_q || tx_frame_inflight_q) begin
          tx_error_q <= 1'b1;
        end else begin
          tx_desc_addr_q <= tx_addr;
          tx_desc_len_q <= tx_len;
          tx_desc_valid_q <= 1'b1;
          tx_busy_q <= 1'b1;
          tx_dma_ok_q <= 1'b0;
          tx_last_byte_sent_q <= 1'b0;
        end
      end
      if (tx_desc_valid_q && tx_desc_ready)
        tx_desc_valid_q <= 1'b0;
      if (dma_read_status_valid && tx_busy_q) begin
        if (|dma_read_status_error) begin
          tx_busy_q <= 1'b0;
          tx_error_q <= 1'b1;
        end else begin
          tx_dma_ok_q <= 1'b1;
        end
      end
      if (tx_byte_valid && tx_byte_ready && tx_byte_last)
        tx_last_byte_sent_q <= 1'b1;
      if (tx_dma_ok_q && tx_last_byte_sent_q && !tx_frame_ready_q &&
          !tx_frame_inflight_q)
        tx_frame_ready_q <= 1'b1;
      if (tx_frame_ready_q && tx_frame_ready_cdc_ready) begin
        tx_frame_ready_q <= 1'b0;
        tx_frame_inflight_q <= 1'b1;
      end
      if (tx_frame_inflight_q && tx_frame_ready_cdc_ready) begin
        tx_frame_inflight_q <= 1'b0;
        tx_busy_q <= 1'b0;
        tx_done_q <= 1'b1;
      end

      if (rx_arm) begin
        if ((rx_addr[2:0] != 3'b000) ||
            (rx_capacity == 0) || (rx_capacity > RX_MAX_FRAME_BYTES)) begin
          rx_error_q <= 1'b1;
        end else begin
          rx_desc_addr_q <= rx_addr;
          rx_busy_q <= 1'b1;
          rx_desc_valid_q <= 1'b0;
          rx_desc_issued_q <= 1'b0;
          rx_buffer_arm_q <= 1'b1;
        end
      end
      if (rx_frame_drop && rx_busy_q) begin
        rx_busy_q <= 1'b0;
        rx_error_q <= 1'b1;
      end
      if (rx_busy_q && rx_frame_ready && !rx_desc_valid_q && !rx_desc_issued_q) begin
        rx_desc_len_q <= rx_frame_len;
        rx_desc_valid_q <= 1'b1;
      end
      if (rx_desc_valid_q && rx_desc_ready) begin
        rx_desc_valid_q <= 1'b0;
        rx_desc_issued_q <= 1'b1;
        rx_buffer_start_q <= 1'b1;
      end
      if (dma_write_status_valid && rx_desc_issued_q) begin
        rx_busy_q <= 1'b0;
        rx_desc_issued_q <= 1'b0;
        rx_done_q <= 1'b1;
        rx_len_q <= dma_write_status_len;
        rx_error_q <= |dma_write_status_error;
        rx_buffer_release_q <= 1'b1;
      end
    end
  end

  ap_eth_axis64_to_axis8 tx_narrow_i (
    .clk(clk),
    .rst_n(rst_n),
    .s_axis_tdata_i(dma_read_data),
    .s_axis_tkeep_i(dma_read_keep),
    .s_axis_tvalid_i(dma_read_valid),
    .s_axis_tready_o(dma_read_ready),
    .s_axis_tlast_i(dma_read_last),
    .s_axis_tuser_i(dma_read_user),
    .m_axis_tdata_o(tx_byte_data),
    .m_axis_tvalid_o(tx_byte_valid),
    .m_axis_tready_i(tx_byte_ready),
    .m_axis_tlast_o(tx_byte_last),
    .m_axis_tuser_o(tx_byte_user)
  );

  cdc_2phase #(
    .T(logic)
  ) tx_frame_ready_cdc_i (
    .src_rst_ni(rst_n),
    .src_clk_i(clk),
    .src_data_i(1'b1),
    .src_valid_i(tx_frame_ready_q),
    .src_ready_o(tx_frame_ready_cdc_ready),
    .dst_rst_ni(eth_tx_rst_n_i),
    .dst_clk_i(eth_tx_clk_i),
    .dst_data_o(),
    .dst_valid_o(tx_frame_ready_phy_valid),
    .dst_ready_i(tx_frame_consumed_phy)
  );

  ap_eth_axis8_cdc #(
    .LOG_DEPTH_P(11)
  ) tx_cdc_i (
    .s_clk_i(clk),
    .s_rst_ni(rst_n),
    .s_axis_tdata_i(tx_byte_data),
    .s_axis_tvalid_i(tx_byte_valid),
    .s_axis_tready_o(tx_byte_ready),
    .s_axis_tlast_i(tx_byte_last),
    .s_axis_tuser_i(tx_byte_user),
    .m_clk_i(eth_tx_clk_i),
    .m_rst_ni(eth_tx_rst_n_i),
    .m_axis_tdata_o(tx_cdc_data),
    .m_axis_tvalid_o(tx_cdc_valid),
    .m_axis_tready_i(tx_frame_ready_phy_valid && mac_tx_ready),
    .m_axis_tlast_o(tx_cdc_last),
    .m_axis_tuser_o(tx_cdc_user)
  );

  ap_eth_axis8_cdc #(
    .LOG_DEPTH_P(11)
  ) rx_cdc_i (
    .s_clk_i(eth_rx_clk_i),
    .s_rst_ni(eth_rx_rst_n_i),
    .s_axis_tdata_i(mac_rx_data),
    .s_axis_tvalid_i(mac_rx_valid),
    .s_axis_tready_o(mac_rx_ready),
    .s_axis_tlast_i(mac_rx_last),
    .s_axis_tuser_i(mac_rx_user),
    .m_clk_i(clk),
    .m_rst_ni(rst_n),
    .m_axis_tdata_o(rx_byte_data),
    .m_axis_tvalid_o(rx_byte_valid),
    .m_axis_tready_i(rx_byte_ready),
    .m_axis_tlast_o(rx_byte_last),
    .m_axis_tuser_o(rx_byte_user)
  );

  ap_eth_rx_frame_buffer #(
    .MAX_FRAME_BYTES_P(RX_MAX_FRAME_BYTES)
  ) rx_frame_buffer_i (
    .clk(clk),
    .rst_n(rst_n),
    .arm_i(rx_buffer_arm_q),
    .capacity_i(rx_capacity),
    .rx_enable_i(rx_enable),
    .s_axis_tdata_i(rx_byte_data),
    .s_axis_tvalid_i(rx_byte_valid),
    .s_axis_tready_o(rx_byte_ready),
    .s_axis_tlast_i(rx_byte_last),
    .s_axis_tuser_i(rx_byte_user),
    .frame_ready_o(rx_frame_ready),
    .frame_len_o(rx_frame_len),
    .frame_drop_o(rx_frame_drop),
    .stream_start_i(rx_buffer_start_q),
    .m_axis_tdata_o(dma_write_data),
    .m_axis_tkeep_o(dma_write_keep),
    .m_axis_tvalid_o(dma_write_valid),
    .m_axis_tready_i(dma_write_ready),
    .m_axis_tlast_o(dma_write_last),
    .release_i(rx_buffer_release_q)
  );

  axi_dma #(
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_MAX_BURST_LEN(16),
    .AXIS_DATA_WIDTH(AP_AXI_DATA_W),
    .AXIS_KEEP_ENABLE(1),
    .AXIS_KEEP_WIDTH(AP_AXI_DATA_W / 8),
    .AXIS_LAST_ENABLE(1),
    .AXIS_ID_ENABLE(0),
    .AXIS_DEST_ENABLE(0),
    .AXIS_USER_ENABLE(1),
    .AXIS_USER_WIDTH(1),
    .LEN_WIDTH(16),
    .TAG_WIDTH(1),
    .ENABLE_SG(0),
    .ENABLE_UNALIGNED(0)
  ) dma_i (
    .clk(clk),
    .rst(!rst_n),
    .s_axis_read_desc_addr(tx_desc_addr_q),
    .s_axis_read_desc_len(tx_desc_len_q),
    .s_axis_read_desc_tag(1'b0),
    .s_axis_read_desc_id('0),
    .s_axis_read_desc_dest('0),
    .s_axis_read_desc_user(1'b0),
    .s_axis_read_desc_valid(tx_desc_valid_q),
    .s_axis_read_desc_ready(tx_desc_ready),
    .m_axis_read_desc_status_tag(),
    .m_axis_read_desc_status_error(dma_read_status_error),
    .m_axis_read_desc_status_valid(dma_read_status_valid),
    .m_axis_read_data_tdata(dma_read_data),
    .m_axis_read_data_tkeep(dma_read_keep),
    .m_axis_read_data_tvalid(dma_read_valid),
    .m_axis_read_data_tready(dma_read_ready),
    .m_axis_read_data_tlast(dma_read_last),
    .m_axis_read_data_tid(),
    .m_axis_read_data_tdest(),
    .m_axis_read_data_tuser(dma_read_user),
    .s_axis_write_desc_addr(rx_desc_addr_q),
    .s_axis_write_desc_len(rx_desc_len_q),
    .s_axis_write_desc_tag(1'b0),
    .s_axis_write_desc_valid(rx_desc_valid_q),
    .s_axis_write_desc_ready(rx_desc_ready),
    .m_axis_write_desc_status_len(dma_write_status_len),
    .m_axis_write_desc_status_tag(),
    .m_axis_write_desc_status_id(),
    .m_axis_write_desc_status_dest(),
    .m_axis_write_desc_status_user(),
    .m_axis_write_desc_status_error(dma_write_status_error),
    .m_axis_write_desc_status_valid(dma_write_status_valid),
    .s_axis_write_data_tdata(dma_write_data),
    .s_axis_write_data_tkeep(dma_write_keep),
    .s_axis_write_data_tvalid(dma_write_valid),
    .s_axis_write_data_tready(dma_write_ready),
    .s_axis_write_data_tlast(dma_write_last),
    .s_axis_write_data_tid('0),
    .s_axis_write_data_tdest('0),
    .s_axis_write_data_tuser(1'b0),
    .m_axi_awid(mem_axi_o.aw_id),
    .m_axi_awaddr(mem_axi_o.aw_addr),
    .m_axi_awlen(mem_axi_o.aw_len),
    .m_axi_awsize(mem_axi_o.aw_size),
    .m_axi_awburst(mem_axi_o.aw_burst),
    .m_axi_awlock(mem_axi_o.aw_lock),
    .m_axi_awcache(mem_axi_o.aw_cache),
    .m_axi_awprot(mem_axi_o.aw_prot),
    .m_axi_awvalid(mem_axi_o.aw_valid),
    .m_axi_awready(mem_axi_o.aw_ready),
    .m_axi_wdata(mem_axi_o.w_data),
    .m_axi_wstrb(mem_axi_o.w_strb),
    .m_axi_wlast(mem_axi_o.w_last),
    .m_axi_wvalid(mem_axi_o.w_valid),
    .m_axi_wready(mem_axi_o.w_ready),
    .m_axi_bid(mem_axi_o.b_id),
    .m_axi_bresp(mem_axi_o.b_resp),
    .m_axi_bvalid(mem_axi_o.b_valid),
    .m_axi_bready(mem_axi_o.b_ready),
    .m_axi_arid(mem_axi_o.ar_id),
    .m_axi_araddr(mem_axi_o.ar_addr),
    .m_axi_arlen(mem_axi_o.ar_len),
    .m_axi_arsize(mem_axi_o.ar_size),
    .m_axi_arburst(mem_axi_o.ar_burst),
    .m_axi_arlock(mem_axi_o.ar_lock),
    .m_axi_arcache(mem_axi_o.ar_cache),
    .m_axi_arprot(mem_axi_o.ar_prot),
    .m_axi_arvalid(mem_axi_o.ar_valid),
    .m_axi_arready(mem_axi_o.ar_ready),
    .m_axi_rid(mem_axi_o.r_id),
    .m_axi_rdata(mem_axi_o.r_data),
    .m_axi_rresp(mem_axi_o.r_resp),
    .m_axi_rlast(mem_axi_o.r_last),
    .m_axi_rvalid(mem_axi_o.r_valid),
    .m_axi_rready(mem_axi_o.r_ready),
    .read_enable(1'b1),
    .write_enable(1'b1),
    .write_abort(1'b0)
  );

  assign mem_axi_o.aw_qos = '0;
  assign mem_axi_o.aw_region = '0;
  assign mem_axi_o.aw_atop = '0;
  assign mem_axi_o.aw_user = '0;
  assign mem_axi_o.w_user = '0;
  assign mem_axi_o.ar_qos = '0;
  assign mem_axi_o.ar_region = '0;
  assign mem_axi_o.ar_user = '0;

  eth_mac_1g mac_i (
    .rx_clk(eth_rx_clk_i),
    .rx_rst(!eth_rx_rst_n_i),
    .tx_clk(eth_tx_clk_i),
    .tx_rst(!eth_tx_rst_n_i),
    .tx_axis_tdata(mac_tx_data),
    .tx_axis_tvalid(mac_tx_valid),
    .tx_axis_tready(mac_tx_ready),
    .tx_axis_tlast(mac_tx_last),
    .tx_axis_tuser(mac_tx_user),
    .rx_axis_tdata(mac_rx_data),
    .rx_axis_tvalid(mac_rx_valid),
    .rx_axis_tlast(mac_rx_last),
    .rx_axis_tuser(mac_rx_user),
    .gmii_rxd(eth_gmii_rxd_i),
    .gmii_rx_dv(eth_gmii_rx_dv_i),
    .gmii_rx_er(eth_gmii_rx_er_i),
    .gmii_txd(eth_gmii_txd_o),
    .gmii_tx_en(eth_gmii_tx_en_o),
    .gmii_tx_er(eth_gmii_tx_er_o),
    .tx_ptp_ts('0),
    .rx_ptp_ts('0),
    .tx_axis_ptp_ts(),
    .tx_axis_ptp_ts_tag(),
    .tx_axis_ptp_ts_valid(),
    .tx_lfc_req(1'b0),
    .tx_lfc_resend(1'b0),
    .rx_lfc_en(1'b0),
    .rx_lfc_req(),
    .rx_lfc_ack(1'b0),
    .tx_pfc_req('0),
    .tx_pfc_resend(1'b0),
    .rx_pfc_en('0),
    .rx_pfc_req(),
    .rx_pfc_ack('0),
    .tx_lfc_pause_en(1'b0),
    .tx_pause_req(1'b0),
    .tx_pause_ack(),
    .rx_clk_enable(1'b1),
    .tx_clk_enable(1'b1),
    .rx_mii_select(1'b0),
    .tx_mii_select(1'b0),
    .tx_start_packet(),
    .tx_error_underflow(),
    .rx_start_packet(),
    .rx_error_bad_frame(),
    .rx_error_bad_fcs(),
    .stat_tx_mcf(),
    .stat_rx_mcf(),
    .stat_tx_lfc_pkt(),
    .stat_tx_lfc_xon(),
    .stat_tx_lfc_xoff(),
    .stat_tx_lfc_paused(),
    .stat_tx_pfc_pkt(),
    .stat_tx_pfc_xon(),
    .stat_tx_pfc_xoff(),
    .stat_tx_pfc_paused(),
    .stat_rx_lfc_pkt(),
    .stat_rx_lfc_xon(),
    .stat_rx_lfc_xoff(),
    .stat_rx_lfc_paused(),
    .stat_rx_pfc_pkt(),
    .stat_rx_pfc_xon(),
    .stat_rx_pfc_xoff(),
    .stat_rx_pfc_paused(),
    .cfg_ifg(8'd12),
    .cfg_tx_enable(tx_enable),
    .cfg_rx_enable(rx_enable),
    .cfg_mcf_rx_eth_dst_mcast('0),
    .cfg_mcf_rx_check_eth_dst_mcast(1'b0),
    .cfg_mcf_rx_eth_dst_ucast('0),
    .cfg_mcf_rx_check_eth_dst_ucast(1'b0),
    .cfg_mcf_rx_eth_src('0),
    .cfg_mcf_rx_check_eth_src(1'b0),
    .cfg_mcf_rx_eth_type('0),
    .cfg_mcf_rx_opcode_lfc('0),
    .cfg_mcf_rx_check_opcode_lfc(1'b0),
    .cfg_mcf_rx_opcode_pfc('0),
    .cfg_mcf_rx_check_opcode_pfc(1'b0),
    .cfg_mcf_rx_forward(1'b0),
    .cfg_mcf_rx_enable(1'b0),
    .cfg_tx_lfc_eth_dst('0),
    .cfg_tx_lfc_eth_src('0),
    .cfg_tx_lfc_eth_type('0),
    .cfg_tx_lfc_opcode('0),
    .cfg_tx_lfc_en(1'b0),
    .cfg_tx_lfc_quanta('0),
    .cfg_tx_lfc_refresh('0),
    .cfg_tx_pfc_eth_dst('0),
    .cfg_tx_pfc_eth_src('0),
    .cfg_tx_pfc_eth_type('0),
    .cfg_tx_pfc_opcode('0),
    .cfg_tx_pfc_en(1'b0),
    .cfg_tx_pfc_quanta('0),
    .cfg_tx_pfc_refresh('0),
    .cfg_rx_lfc_opcode('0),
    .cfg_rx_lfc_en(1'b0),
    .cfg_rx_pfc_opcode('0),
    .cfg_rx_pfc_en(1'b0)
  );

endmodule
