// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Tie off a reserved AP AXI ingress until its master exists. Responses are
// accepted so a malformed external transaction cannot wedge the fabric.
module ap_axi64_idle_master (
  AXI_BUS.Master m_axi_o
);

  assign m_axi_o.aw_id = '0;
  assign m_axi_o.aw_addr = '0;
  assign m_axi_o.aw_len = '0;
  assign m_axi_o.aw_size = '0;
  assign m_axi_o.aw_burst = '0;
  assign m_axi_o.aw_lock = 1'b0;
  assign m_axi_o.aw_cache = '0;
  assign m_axi_o.aw_prot = '0;
  assign m_axi_o.aw_qos = '0;
  assign m_axi_o.aw_region = '0;
  assign m_axi_o.aw_atop = '0;
  assign m_axi_o.aw_user = '0;
  assign m_axi_o.aw_valid = 1'b0;

  assign m_axi_o.w_data = '0;
  assign m_axi_o.w_strb = '0;
  assign m_axi_o.w_last = 1'b0;
  assign m_axi_o.w_user = '0;
  assign m_axi_o.w_valid = 1'b0;
  assign m_axi_o.b_ready = 1'b1;

  assign m_axi_o.ar_id = '0;
  assign m_axi_o.ar_addr = '0;
  assign m_axi_o.ar_len = '0;
  assign m_axi_o.ar_size = '0;
  assign m_axi_o.ar_burst = '0;
  assign m_axi_o.ar_lock = 1'b0;
  assign m_axi_o.ar_cache = '0;
  assign m_axi_o.ar_prot = '0;
  assign m_axi_o.ar_qos = '0;
  assign m_axi_o.ar_region = '0;
  assign m_axi_o.ar_user = '0;
  assign m_axi_o.ar_valid = 1'b0;
  assign m_axi_o.r_ready = 1'b1;

endmodule
