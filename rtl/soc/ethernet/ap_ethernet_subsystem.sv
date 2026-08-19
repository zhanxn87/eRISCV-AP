// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Ethernet subsystem boundary: APB descriptor-ring control, 64-bit AXI4 DMA,
// PHY-clock CDC, and a GMII 1G MAC.  The ring engine self-fetches descriptors
// from DDR and writes completion status after the payload DMA has finished.
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
  input logic eth_gmii_clk_enable_i,
  output logic [7:0] eth_gmii_txd_o,
  output logic eth_gmii_tx_en_o,
  output logic eth_gmii_tx_er_o,

  output logic irq_o,
  AXI_BUS.Master mem_axi_o
);

  localparam logic [15:0] RX_MAX_FRAME_BYTES = 16'd2048;
  localparam logic [15:0] TX_MAX_FRAME_BYTES = 16'd1536;
  localparam int unsigned ETH_AXI_ID_W = AP_AXI_SLV_ID_W - 1;

  logic tx_enable;
  logic ring_reset;
  logic rx_enable;
  logic [47:0] tx_ring_base;
  logic [15:0] tx_ring_count;
  logic [15:0] tx_tail;
  logic tx_doorbell;
  logic [15:0] tx_head;
  logic tx_ring_busy;
  logic [47:0] rx_ring_base;
  logic [15:0] rx_ring_count;
  logic [15:0] rx_tail;
  logic rx_doorbell;
  logic [15:0] rx_head;
  logic rx_ring_busy;
  logic tx_done;
  logic tx_error;
  logic rx_done;
  logic rx_error;

  logic tx_launch_valid;
  logic tx_launch_ready;
  logic [47:0] tx_launch_addr;
  logic [15:0] tx_launch_len;
  logic tx_complete_valid_q;
  logic tx_complete_error_q;
  logic rx_arm_valid;
  logic rx_arm_ready;
  logic [47:0] rx_arm_addr;
  logic [15:0] rx_arm_capacity;
  logic rx_complete_valid_q;
  logic [15:0] rx_complete_len_q;
  logic rx_complete_error_q;

  logic tx_busy_q;
  logic tx_dma_ok_q;
  logic tx_last_byte_sent_q;
  logic tx_frame_ready_q;
  logic tx_frame_ready_cdc_ready;
  logic tx_frame_inflight_q;
  logic tx_frame_ready_phy_valid;
  logic tx_frame_complete_phy;

  logic rx_busy_q;

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
  logic [15:0] rx_buffer_capacity_q;
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
  logic [7:0] tx_phy_data;
  logic tx_phy_valid;
  logic tx_phy_ready;
  logic tx_phy_last;
  logic tx_phy_user;
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

  AXI_BUS #(
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_ID_WIDTH(ETH_AXI_ID_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W)
  ) eth_axi [1:0] ();

  assign tx_launch_ready = !tx_busy_q && !tx_desc_valid_q && !tx_frame_ready_q &&
                           !tx_frame_inflight_q && tx_frame_ready_cdc_ready;
  assign rx_arm_ready = !rx_busy_q && !rx_desc_valid_q && !rx_desc_issued_q &&
                        !rx_frame_ready;



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
    .ring_reset_o(ring_reset),
    .rx_enable_o(rx_enable),
    .tx_ring_base_o(tx_ring_base),
    .tx_ring_count_o(tx_ring_count),
    .tx_tail_o(tx_tail),
    .tx_doorbell_o(tx_doorbell),
    .tx_head_i(tx_head),
    .tx_busy_i(tx_ring_busy),
    .tx_done_i(tx_done),
    .tx_error_i(tx_error),
    .rx_ring_base_o(rx_ring_base),
    .rx_ring_count_o(rx_ring_count),
    .rx_tail_o(rx_tail),
    .rx_doorbell_o(rx_doorbell),
    .rx_head_i(rx_head),
    .rx_busy_i(rx_ring_busy),
    .rx_done_i(rx_done),
    .rx_error_i(rx_error),
    .irq_o(irq_o)
  );

  ap_eth_ring_engine #(
    .TX_MAX_BYTES_P(TX_MAX_FRAME_BYTES),
    .RX_MAX_BYTES_P(RX_MAX_FRAME_BYTES)
  ) ring_engine_i (
    .clk(clk),
    .rst_n(rst_n),
    .tx_enable_i(tx_enable),
    .ring_reset_i(ring_reset),
    .tx_ring_base_i(tx_ring_base),
    .tx_ring_count_i(tx_ring_count),
    .tx_tail_i(tx_tail),
    .tx_doorbell_i(tx_doorbell),
    .tx_head_o(tx_head),
    .tx_busy_o(tx_ring_busy),
    .rx_enable_i(rx_enable),
    .rx_ring_base_i(rx_ring_base),
    .rx_ring_count_i(rx_ring_count),
    .rx_tail_i(rx_tail),
    .rx_doorbell_i(rx_doorbell),
    .rx_head_o(rx_head),
    .rx_busy_o(rx_ring_busy),
    .tx_launch_valid_o(tx_launch_valid),
    .tx_launch_ready_i(tx_launch_ready),
    .tx_launch_addr_o(tx_launch_addr),
    .tx_launch_len_o(tx_launch_len),
    .tx_complete_valid_i(tx_complete_valid_q),
    .tx_complete_error_i(tx_complete_error_q),
    .rx_arm_valid_o(rx_arm_valid),
    .rx_arm_ready_i(rx_arm_ready),
    .rx_arm_addr_o(rx_arm_addr),
    .rx_arm_capacity_o(rx_arm_capacity),
    .rx_complete_valid_i(rx_complete_valid_q),
    .rx_complete_len_i(rx_complete_len_q),
    .rx_complete_error_i(rx_complete_error_q),
    .tx_done_o(tx_done),
    .tx_error_o(tx_error),
    .rx_done_o(rx_done),
    .rx_error_o(rx_error),
    .desc_axi_o(eth_axi[0])
  );

  // The descriptor engine launches one operation per direction.  TX completion
  // is delayed until the PHY staging buffer and MAC accept the last byte; RX completion is delayed until
  // the DMA write response, so descriptor DONE is an ownership hand-off.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_busy_q <= 1'b0;
      tx_dma_ok_q <= 1'b0;
      tx_last_byte_sent_q <= 1'b0;
      tx_frame_ready_q <= 1'b0;
      tx_frame_inflight_q <= 1'b0;
      tx_desc_valid_q <= 1'b0;
      tx_desc_addr_q <= '0;
      tx_desc_len_q <= '0;
      tx_complete_valid_q <= 1'b0;
      tx_complete_error_q <= 1'b0;
      rx_busy_q <= 1'b0;
      rx_desc_valid_q <= 1'b0;
      rx_desc_issued_q <= 1'b0;
      rx_desc_addr_q <= '0;
      rx_desc_len_q <= '0;
      rx_buffer_arm_q <= 1'b0;
      rx_buffer_capacity_q <= '0;
      rx_buffer_start_q <= 1'b0;
      rx_buffer_release_q <= 1'b0;
      rx_complete_valid_q <= 1'b0;
      rx_complete_len_q <= '0;
      rx_complete_error_q <= 1'b0;
    end else begin
      tx_complete_valid_q <= 1'b0;
      tx_complete_error_q <= 1'b0;
      rx_buffer_arm_q <= 1'b0;
      rx_buffer_start_q <= 1'b0;
      rx_buffer_release_q <= 1'b0;
      rx_complete_valid_q <= 1'b0;
      rx_complete_error_q <= 1'b0;

      if (tx_launch_valid && tx_launch_ready) begin
        tx_desc_addr_q <= tx_launch_addr;
        tx_desc_len_q <= tx_launch_len;
        tx_desc_valid_q <= 1'b1;
        tx_busy_q <= 1'b1;
        tx_dma_ok_q <= 1'b0;
        tx_last_byte_sent_q <= 1'b0;
      end
      if (tx_desc_valid_q && tx_desc_ready)
        tx_desc_valid_q <= 1'b0;
      if (dma_read_status_valid && tx_busy_q) begin
        if (|dma_read_status_error) begin
          tx_busy_q <= 1'b0;
          tx_complete_valid_q <= 1'b1;
          tx_complete_error_q <= 1'b1;
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
        tx_dma_ok_q <= 1'b0;
        tx_last_byte_sent_q <= 1'b0;
        tx_complete_valid_q <= 1'b1;
      end

      if (rx_arm_valid && rx_arm_ready) begin
        rx_desc_addr_q <= rx_arm_addr;
        rx_busy_q <= 1'b1;
        rx_desc_valid_q <= 1'b0;
        rx_desc_issued_q <= 1'b0;
        rx_buffer_capacity_q <= rx_arm_capacity;
        rx_buffer_arm_q <= 1'b1;
      end
      if (rx_frame_drop && rx_busy_q) begin
        rx_busy_q <= 1'b0;
        rx_complete_valid_q <= 1'b1;
        rx_complete_error_q <= 1'b1;
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
        rx_complete_valid_q <= 1'b1;
        rx_complete_len_q <= dma_write_status_len;
        rx_complete_error_q <= |dma_write_status_error;
        rx_buffer_release_q <= 1'b1;
      end

      if (!rx_enable && !rx_desc_issued_q) begin
        rx_busy_q <= 1'b0;
        rx_desc_valid_q <= 1'b0;
        rx_complete_valid_q <= 1'b0;
        rx_complete_error_q <= 1'b0;
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
    .dst_ready_i(tx_frame_complete_phy)
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
    .m_axis_tdata_o(tx_phy_data),
    .m_axis_tvalid_o(tx_phy_valid),
    .m_axis_tready_i(tx_phy_ready),
    .m_axis_tlast_o(tx_phy_last),
    .m_axis_tuser_o(tx_phy_user)
  );

  ap_eth_tx_frame_buffer #(
    .MAX_FRAME_BYTES_P(TX_MAX_FRAME_BYTES)
  ) tx_frame_buffer_i (
    .clk(eth_tx_clk_i),
    .rst_n(eth_tx_rst_n_i),
    .frame_start_i(tx_frame_ready_phy_valid),
    .s_axis_tdata_i(tx_phy_data),
    .s_axis_tvalid_i(tx_phy_valid),
    .s_axis_tready_o(tx_phy_ready),
    .s_axis_tlast_i(tx_phy_last),
    .s_axis_tuser_i(tx_phy_user),
    .m_axis_tdata_o(mac_tx_data),
    .m_axis_tvalid_o(mac_tx_valid),
    .m_axis_tready_i(mac_tx_ready),
    .m_axis_tlast_o(mac_tx_last),
    .m_axis_tuser_o(mac_tx_user),
    .frame_complete_o(tx_frame_complete_phy)
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
    .capacity_i(rx_buffer_capacity_q),
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
    .AXI_ID_WIDTH(ETH_AXI_ID_W),
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
    .m_axi_awid(eth_axi[1].aw_id),
    .m_axi_awaddr(eth_axi[1].aw_addr),
    .m_axi_awlen(eth_axi[1].aw_len),
    .m_axi_awsize(eth_axi[1].aw_size),
    .m_axi_awburst(eth_axi[1].aw_burst),
    .m_axi_awlock(eth_axi[1].aw_lock),
    .m_axi_awcache(eth_axi[1].aw_cache),
    .m_axi_awprot(eth_axi[1].aw_prot),
    .m_axi_awvalid(eth_axi[1].aw_valid),
    .m_axi_awready(eth_axi[1].aw_ready),
    .m_axi_wdata(eth_axi[1].w_data),
    .m_axi_wstrb(eth_axi[1].w_strb),
    .m_axi_wlast(eth_axi[1].w_last),
    .m_axi_wvalid(eth_axi[1].w_valid),
    .m_axi_wready(eth_axi[1].w_ready),
    .m_axi_bid(eth_axi[1].b_id),
    .m_axi_bresp(eth_axi[1].b_resp),
    .m_axi_bvalid(eth_axi[1].b_valid),
    .m_axi_bready(eth_axi[1].b_ready),
    .m_axi_arid(eth_axi[1].ar_id),
    .m_axi_araddr(eth_axi[1].ar_addr),
    .m_axi_arlen(eth_axi[1].ar_len),
    .m_axi_arsize(eth_axi[1].ar_size),
    .m_axi_arburst(eth_axi[1].ar_burst),
    .m_axi_arlock(eth_axi[1].ar_lock),
    .m_axi_arcache(eth_axi[1].ar_cache),
    .m_axi_arprot(eth_axi[1].ar_prot),
    .m_axi_arvalid(eth_axi[1].ar_valid),
    .m_axi_arready(eth_axi[1].ar_ready),
    .m_axi_rid(eth_axi[1].r_id),
    .m_axi_rdata(eth_axi[1].r_data),
    .m_axi_rresp(eth_axi[1].r_resp),
    .m_axi_rlast(eth_axi[1].r_last),
    .m_axi_rvalid(eth_axi[1].r_valid),
    .m_axi_rready(eth_axi[1].r_ready),
    .read_enable(1'b1),
    .write_enable(1'b1),
    .write_abort(1'b0)
  );

  axi_mux_intf #(
    .SLV_AXI_ID_WIDTH(ETH_AXI_ID_W),
    .MST_AXI_ID_WIDTH(AP_AXI_SLV_ID_W),
    .AXI_ADDR_WIDTH(AP_PADDR_W),
    .AXI_DATA_WIDTH(AP_AXI_DATA_W),
    .AXI_USER_WIDTH(AP_AXI_USER_W),
    .NO_SLV_PORTS(2),
    .MAX_W_TRANS(2)
  ) axi_mux_i (
    .clk_i(clk),
    .rst_ni(rst_n),
    .test_i(1'b0),
    .slv(eth_axi),
    .mst(mem_axi_o)
  );

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
    .rx_clk_enable(eth_gmii_clk_enable_i),
    .tx_clk_enable(eth_gmii_clk_enable_i),
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
