// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// One-manager AXI4 router for the uncached peripheral tree.  It keeps the
// local CLINT/PLIC/APB slave and the external BPI egress disjoint while
// preserving write-data routing after AW has completed.
module ap_axi64_peripheral_router
  import ap_soc_pkg::*;
(
  input logic clk,
  input logic rst_n,
  AXI_BUS.Slave s_axi_i,
  AXI_BUS.Master local_axi_o,
  AXI_BUS.Master bpi_axi_o
);

  logic wr_aw_pending_q;
  logic wr_resp_pending_q;
  logic wr_bpi_q;
  logic rd_pending_q;
  logic rd_bpi_q;
  logic aw_to_bpi;
  logic ar_to_bpi;
  logic write_start_ready;
  logic read_start_ready;
  logic aw_fire;
  logic w_fire;
  logic b_fire;
  logic ar_fire;
  logic r_fire;

  assign aw_to_bpi = ap_addr_in_range(s_axi_i.aw_addr, AP_BPI_BASE, AP_BPI_LIMIT);
  assign ar_to_bpi = ap_addr_in_range(s_axi_i.ar_addr, AP_BPI_BASE, AP_BPI_LIMIT);
  assign write_start_ready = !wr_aw_pending_q && !wr_resp_pending_q && !rd_pending_q;
  assign read_start_ready = !rd_pending_q && !wr_aw_pending_q &&
                            !wr_resp_pending_q && !s_axi_i.aw_valid;

  assign local_axi_o.aw_id = s_axi_i.aw_id;
  assign local_axi_o.aw_addr = s_axi_i.aw_addr;
  assign local_axi_o.aw_len = s_axi_i.aw_len;
  assign local_axi_o.aw_size = s_axi_i.aw_size;
  assign local_axi_o.aw_burst = s_axi_i.aw_burst;
  assign local_axi_o.aw_lock = s_axi_i.aw_lock;
  assign local_axi_o.aw_cache = s_axi_i.aw_cache;
  assign local_axi_o.aw_prot = s_axi_i.aw_prot;
  assign local_axi_o.aw_qos = s_axi_i.aw_qos;
  assign local_axi_o.aw_region = s_axi_i.aw_region;
  assign local_axi_o.aw_atop = s_axi_i.aw_atop;
  assign local_axi_o.aw_user = s_axi_i.aw_user;
  assign local_axi_o.aw_valid = s_axi_i.aw_valid && write_start_ready && !aw_to_bpi;

  assign bpi_axi_o.aw_id = s_axi_i.aw_id;
  assign bpi_axi_o.aw_addr = s_axi_i.aw_addr;
  assign bpi_axi_o.aw_len = s_axi_i.aw_len;
  assign bpi_axi_o.aw_size = s_axi_i.aw_size;
  assign bpi_axi_o.aw_burst = s_axi_i.aw_burst;
  assign bpi_axi_o.aw_lock = s_axi_i.aw_lock;
  assign bpi_axi_o.aw_cache = s_axi_i.aw_cache;
  assign bpi_axi_o.aw_prot = s_axi_i.aw_prot;
  assign bpi_axi_o.aw_qos = s_axi_i.aw_qos;
  assign bpi_axi_o.aw_region = s_axi_i.aw_region;
  assign bpi_axi_o.aw_atop = s_axi_i.aw_atop;
  assign bpi_axi_o.aw_user = s_axi_i.aw_user;
  assign bpi_axi_o.aw_valid = s_axi_i.aw_valid && write_start_ready && aw_to_bpi;

  assign s_axi_i.aw_ready = write_start_ready &&
                            (aw_to_bpi ? bpi_axi_o.aw_ready : local_axi_o.aw_ready);
  assign aw_fire = s_axi_i.aw_valid && s_axi_i.aw_ready;

  assign local_axi_o.w_data = s_axi_i.w_data;
  assign local_axi_o.w_strb = s_axi_i.w_strb;
  assign local_axi_o.w_last = s_axi_i.w_last;
  assign local_axi_o.w_user = s_axi_i.w_user;
  assign local_axi_o.w_valid = s_axi_i.w_valid && wr_aw_pending_q && !wr_bpi_q;

  assign bpi_axi_o.w_data = s_axi_i.w_data;
  assign bpi_axi_o.w_strb = s_axi_i.w_strb;
  assign bpi_axi_o.w_last = s_axi_i.w_last;
  assign bpi_axi_o.w_user = s_axi_i.w_user;
  assign bpi_axi_o.w_valid = s_axi_i.w_valid && wr_aw_pending_q && wr_bpi_q;

  assign s_axi_i.w_ready = wr_aw_pending_q && !wr_resp_pending_q &&
                           (wr_bpi_q ? bpi_axi_o.w_ready : local_axi_o.w_ready);
  assign w_fire = s_axi_i.w_valid && s_axi_i.w_ready;

  assign s_axi_i.b_id = wr_bpi_q ? bpi_axi_o.b_id : local_axi_o.b_id;
  assign s_axi_i.b_resp = wr_bpi_q ? bpi_axi_o.b_resp : local_axi_o.b_resp;
  assign s_axi_i.b_user = wr_bpi_q ? bpi_axi_o.b_user : local_axi_o.b_user;
  assign s_axi_i.b_valid = wr_resp_pending_q &&
                           (wr_bpi_q ? bpi_axi_o.b_valid : local_axi_o.b_valid);
  assign local_axi_o.b_ready = s_axi_i.b_ready && wr_resp_pending_q && !wr_bpi_q;
  assign bpi_axi_o.b_ready = s_axi_i.b_ready && wr_resp_pending_q && wr_bpi_q;
  assign b_fire = s_axi_i.b_valid && s_axi_i.b_ready;

  assign local_axi_o.ar_id = s_axi_i.ar_id;
  assign local_axi_o.ar_addr = s_axi_i.ar_addr;
  assign local_axi_o.ar_len = s_axi_i.ar_len;
  assign local_axi_o.ar_size = s_axi_i.ar_size;
  assign local_axi_o.ar_burst = s_axi_i.ar_burst;
  assign local_axi_o.ar_lock = s_axi_i.ar_lock;
  assign local_axi_o.ar_cache = s_axi_i.ar_cache;
  assign local_axi_o.ar_prot = s_axi_i.ar_prot;
  assign local_axi_o.ar_qos = s_axi_i.ar_qos;
  assign local_axi_o.ar_region = s_axi_i.ar_region;
  assign local_axi_o.ar_user = s_axi_i.ar_user;
  assign local_axi_o.ar_valid = s_axi_i.ar_valid && read_start_ready && !ar_to_bpi;

  assign bpi_axi_o.ar_id = s_axi_i.ar_id;
  assign bpi_axi_o.ar_addr = s_axi_i.ar_addr;
  assign bpi_axi_o.ar_len = s_axi_i.ar_len;
  assign bpi_axi_o.ar_size = s_axi_i.ar_size;
  assign bpi_axi_o.ar_burst = s_axi_i.ar_burst;
  assign bpi_axi_o.ar_lock = s_axi_i.ar_lock;
  assign bpi_axi_o.ar_cache = s_axi_i.ar_cache;
  assign bpi_axi_o.ar_prot = s_axi_i.ar_prot;
  assign bpi_axi_o.ar_qos = s_axi_i.ar_qos;
  assign bpi_axi_o.ar_region = s_axi_i.ar_region;
  assign bpi_axi_o.ar_user = s_axi_i.ar_user;
  assign bpi_axi_o.ar_valid = s_axi_i.ar_valid && read_start_ready && ar_to_bpi;

  assign s_axi_i.ar_ready = read_start_ready &&
                            (ar_to_bpi ? bpi_axi_o.ar_ready : local_axi_o.ar_ready);
  assign ar_fire = s_axi_i.ar_valid && s_axi_i.ar_ready;

  assign s_axi_i.r_id = rd_bpi_q ? bpi_axi_o.r_id : local_axi_o.r_id;
  assign s_axi_i.r_data = rd_bpi_q ? bpi_axi_o.r_data : local_axi_o.r_data;
  assign s_axi_i.r_resp = rd_bpi_q ? bpi_axi_o.r_resp : local_axi_o.r_resp;
  assign s_axi_i.r_last = rd_bpi_q ? bpi_axi_o.r_last : local_axi_o.r_last;
  assign s_axi_i.r_user = rd_bpi_q ? bpi_axi_o.r_user : local_axi_o.r_user;
  assign s_axi_i.r_valid = rd_pending_q &&
                           (rd_bpi_q ? bpi_axi_o.r_valid : local_axi_o.r_valid);
  assign local_axi_o.r_ready = s_axi_i.r_ready && rd_pending_q && !rd_bpi_q;
  assign bpi_axi_o.r_ready = s_axi_i.r_ready && rd_pending_q && rd_bpi_q;
  assign r_fire = s_axi_i.r_valid && s_axi_i.r_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_aw_pending_q <= 1'b0;
      wr_resp_pending_q <= 1'b0;
      wr_bpi_q <= 1'b0;
      rd_pending_q <= 1'b0;
      rd_bpi_q <= 1'b0;
    end else begin
      if (aw_fire) begin
        wr_aw_pending_q <= 1'b1;
        wr_bpi_q <= aw_to_bpi;
      end
      if (w_fire) begin
        wr_aw_pending_q <= 1'b0;
        wr_resp_pending_q <= 1'b1;
      end
      if (b_fire)
        wr_resp_pending_q <= 1'b0;
      if (ar_fire) begin
        rd_pending_q <= 1'b1;
        rd_bpi_q <= ar_to_bpi;
      end
      if (r_fire)
        rd_pending_q <= 1'b0;
    end
  end

endmodule
