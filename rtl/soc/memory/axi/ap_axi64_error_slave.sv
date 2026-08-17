// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// One-request AXI4 DECERR slave used for an address path that must be absent
// from a subsystem. It preserves AXI write/read completion so an accidental
// misroute cannot wedge the fabric.
module ap_axi64_error_slave
  import ap_soc_pkg::*;
(
  input logic clk,
  input logic rst_n,
  AXI_BUS.Slave s_axi_i
);

  localparam logic [1:0] AXI_RESP_DECERR = 2'b11;

  logic aw_seen_q, w_seen_q, bvalid_q;
  logic [AP_AXI_SLV_ID_W-1:0] bid_q, rid_q;
  logic rvalid_q;
  logic aw_fire, w_fire;

  assign aw_fire = s_axi_i.aw_valid && s_axi_i.aw_ready;
  assign w_fire = s_axi_i.w_valid && s_axi_i.w_ready;
  assign s_axi_i.aw_ready = !bvalid_q && !aw_seen_q;
  assign s_axi_i.w_ready = !bvalid_q && !w_seen_q;
  assign s_axi_i.b_id = bid_q;
  assign s_axi_i.b_resp = AXI_RESP_DECERR;
  assign s_axi_i.b_user = '0;
  assign s_axi_i.b_valid = bvalid_q;

  assign s_axi_i.ar_ready = !rvalid_q;
  assign s_axi_i.r_id = rid_q;
  assign s_axi_i.r_data = '0;
  assign s_axi_i.r_resp = AXI_RESP_DECERR;
  assign s_axi_i.r_last = 1'b1;
  assign s_axi_i.r_user = '0;
  assign s_axi_i.r_valid = rvalid_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_seen_q <= 1'b0;
      w_seen_q <= 1'b0;
      bvalid_q <= 1'b0;
      bid_q <= '0;
      rid_q <= '0;
      rvalid_q <= 1'b0;
    end else begin
      if (aw_fire) begin
        aw_seen_q <= 1'b1;
        bid_q <= s_axi_i.aw_id;
      end
      if (w_fire)
        w_seen_q <= 1'b1;
      if (!bvalid_q && (aw_seen_q || aw_fire) && (w_seen_q || w_fire))
        bvalid_q <= 1'b1;
      if (bvalid_q && s_axi_i.b_ready) begin
        bvalid_q <= 1'b0;
        aw_seen_q <= 1'b0;
        w_seen_q <= 1'b0;
      end
      if (s_axi_i.ar_valid && s_axi_i.ar_ready) begin
        rid_q <= s_axi_i.ar_id;
        rvalid_q <= 1'b1;
      end
      if (rvalid_q && s_axi_i.r_ready)
        rvalid_q <= 1'b0;
    end
  end

endmodule
