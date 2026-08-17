// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Blocking single-beat 64-bit AXI master for CPU device accesses. It owns no
// cache policy and accepts no atomics; dcache_cpu_router rejects uncached
// LR/SC and AMOs before they reach this block.
module ap_uncached_axi_master
  import ap_soc_pkg::*;
#(
  parameter logic [AP_AXI_SLV_ID_W-1:0] AXI_ID_P = 4'd1
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         cpu_req_i,
  input  logic [AP_PADDR_W-1:0]        cpu_addr_i,
  input  logic [63:0]                  cpu_wdata_i,
  input  logic                         cpu_we_i,
  input  logic [7:0]                   cpu_be_i,
  output logic                         cpu_resp_valid_o,
  output logic [63:0]                  cpu_rdata_o,
  output logic                         cpu_err_o,

  AXI_BUS.Master m_axi_o
);

  localparam logic [1:0] AXI_BURST_INCR = 2'b01;
  localparam logic [1:0] AXI_RESP_OKAY = 2'b00;

  typedef enum logic [2:0] {
    UC_IDLE, UC_WRITE_ADDR, UC_WRITE_DATA, UC_WRITE_RESP,
    UC_READ_ADDR, UC_READ_DATA, UC_RESP
  } state_e;

  state_e state_q;
  logic [AP_PADDR_W-1:0] addr_q;
  logic [63:0] wdata_q, rdata_q;
  logic [7:0] be_q;
  logic err_q;

  always_comb begin
    m_axi_o.aw_id = AXI_ID_P;
    m_axi_o.aw_addr = {addr_q[AP_PADDR_W-1:3], 3'b000};
    m_axi_o.aw_len = 8'd0;
    m_axi_o.aw_size = 3'd3;
    m_axi_o.aw_burst = AXI_BURST_INCR;
    m_axi_o.aw_lock = 1'b0;
    m_axi_o.aw_cache = 4'b0000;
    m_axi_o.aw_prot = '0;
    m_axi_o.aw_qos = '0;
    m_axi_o.aw_region = '0;
    m_axi_o.aw_atop = '0;
    m_axi_o.aw_user = '0;
    m_axi_o.aw_valid = state_q == UC_WRITE_ADDR;

    m_axi_o.w_data = wdata_q;
    m_axi_o.w_strb = be_q;
    m_axi_o.w_last = 1'b1;
    m_axi_o.w_user = '0;
    m_axi_o.w_valid = state_q == UC_WRITE_DATA;
    m_axi_o.b_ready = state_q == UC_WRITE_RESP;

    m_axi_o.ar_id = AXI_ID_P;
    m_axi_o.ar_addr = {addr_q[AP_PADDR_W-1:3], 3'b000};
    m_axi_o.ar_len = 8'd0;
    m_axi_o.ar_size = 3'd3;
    m_axi_o.ar_burst = AXI_BURST_INCR;
    m_axi_o.ar_lock = 1'b0;
    m_axi_o.ar_cache = 4'b0000;
    m_axi_o.ar_prot = '0;
    m_axi_o.ar_qos = '0;
    m_axi_o.ar_region = '0;
    m_axi_o.ar_user = '0;
    m_axi_o.ar_valid = state_q == UC_READ_ADDR;
    m_axi_o.r_ready = state_q == UC_READ_DATA;

    cpu_resp_valid_o = state_q == UC_RESP;
    cpu_rdata_o = rdata_q;
    cpu_err_o = err_q;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= UC_IDLE;
      addr_q <= '0;
      wdata_q <= '0;
      be_q <= '0;
      rdata_q <= '0;
      err_q <= 1'b0;
    end else begin
      unique case (state_q)
        UC_IDLE: begin
          if (cpu_req_i) begin
            addr_q <= cpu_addr_i;
            wdata_q <= cpu_wdata_i;
            be_q <= cpu_we_i ? cpu_be_i : 8'h00;
            err_q <= 1'b0;
            state_q <= cpu_we_i ? UC_WRITE_ADDR : UC_READ_ADDR;
          end
        end
        UC_WRITE_ADDR:
          if (m_axi_o.aw_ready)
            state_q <= UC_WRITE_DATA;
        UC_WRITE_DATA:
          if (m_axi_o.w_ready)
            state_q <= UC_WRITE_RESP;
        UC_WRITE_RESP: begin
          if (m_axi_o.b_valid) begin
            err_q <= (m_axi_o.b_id != AXI_ID_P) || (m_axi_o.b_resp != AXI_RESP_OKAY);
            state_q <= UC_RESP;
          end
        end
        UC_READ_ADDR:
          if (m_axi_o.ar_ready)
            state_q <= UC_READ_DATA;
        UC_READ_DATA: begin
          if (m_axi_o.r_valid) begin
            rdata_q <= m_axi_o.r_data;
            err_q <= (m_axi_o.r_id != AXI_ID_P) ||
                     (m_axi_o.r_resp != AXI_RESP_OKAY) || !m_axi_o.r_last;
            state_q <= UC_RESP;
          end
        end
        UC_RESP: state_q <= UC_IDLE;
        default: state_q <= UC_IDLE;
      endcase
    end
  end

endmodule
