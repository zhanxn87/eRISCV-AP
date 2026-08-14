// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Explicit AP AXI interface relay. It is intentionally policy-free: address
// decode and ID reduction are owned by the enclosing AXI fabric.
module ap_axi64_egress_bridge (
  AXI_BUS.Slave  s_axi_i,
  AXI_BUS.Master m_axi_o
);

  assign m_axi_o.aw_id = s_axi_i.aw_id;
  assign m_axi_o.aw_addr = s_axi_i.aw_addr;
  assign m_axi_o.aw_len = s_axi_i.aw_len;
  assign m_axi_o.aw_size = s_axi_i.aw_size;
  assign m_axi_o.aw_burst = s_axi_i.aw_burst;
  assign m_axi_o.aw_lock = s_axi_i.aw_lock;
  assign m_axi_o.aw_cache = s_axi_i.aw_cache;
  assign m_axi_o.aw_prot = s_axi_i.aw_prot;
  assign m_axi_o.aw_qos = s_axi_i.aw_qos;
  assign m_axi_o.aw_region = s_axi_i.aw_region;
  assign m_axi_o.aw_atop = s_axi_i.aw_atop;
  assign m_axi_o.aw_user = s_axi_i.aw_user;
  assign m_axi_o.aw_valid = s_axi_i.aw_valid;
  assign s_axi_i.aw_ready = m_axi_o.aw_ready;

  assign m_axi_o.w_data = s_axi_i.w_data;
  assign m_axi_o.w_strb = s_axi_i.w_strb;
  assign m_axi_o.w_last = s_axi_i.w_last;
  assign m_axi_o.w_user = s_axi_i.w_user;
  assign m_axi_o.w_valid = s_axi_i.w_valid;
  assign s_axi_i.w_ready = m_axi_o.w_ready;

  assign s_axi_i.b_id = m_axi_o.b_id;
  assign s_axi_i.b_resp = m_axi_o.b_resp;
  assign s_axi_i.b_user = m_axi_o.b_user;
  assign s_axi_i.b_valid = m_axi_o.b_valid;
  assign m_axi_o.b_ready = s_axi_i.b_ready;

  assign m_axi_o.ar_id = s_axi_i.ar_id;
  assign m_axi_o.ar_addr = s_axi_i.ar_addr;
  assign m_axi_o.ar_len = s_axi_i.ar_len;
  assign m_axi_o.ar_size = s_axi_i.ar_size;
  assign m_axi_o.ar_burst = s_axi_i.ar_burst;
  assign m_axi_o.ar_lock = s_axi_i.ar_lock;
  assign m_axi_o.ar_cache = s_axi_i.ar_cache;
  assign m_axi_o.ar_prot = s_axi_i.ar_prot;
  assign m_axi_o.ar_qos = s_axi_i.ar_qos;
  assign m_axi_o.ar_region = s_axi_i.ar_region;
  assign m_axi_o.ar_user = s_axi_i.ar_user;
  assign m_axi_o.ar_valid = s_axi_i.ar_valid;
  assign s_axi_i.ar_ready = m_axi_o.ar_ready;

  assign s_axi_i.r_id = m_axi_o.r_id;
  assign s_axi_i.r_data = m_axi_o.r_data;
  assign s_axi_i.r_resp = m_axi_o.r_resp;
  assign s_axi_i.r_last = m_axi_o.r_last;
  assign s_axi_i.r_user = m_axi_o.r_user;
  assign s_axi_i.r_valid = m_axi_o.r_valid;
  assign m_axi_o.r_ready = s_axi_i.r_ready;

endmodule
