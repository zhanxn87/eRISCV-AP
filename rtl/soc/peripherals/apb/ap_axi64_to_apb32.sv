// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Blocking AXI4-to-APB bridge. AP harts issue aligned 64-bit single beats;
// each transaction is serialized into ordered 32-bit APB word accesses. WSTRB
// selects the write byte lanes for each APB transfer.
module ap_axi64_to_apb32
  import ap_soc_pkg::*;
(
  input logic clk,
  input logic rst_n,
  AXI_BUS.Slave s_axi_i,

  output logic apb_psel_o,
  output logic apb_penable_o,
  output logic apb_pwrite_o,
  output logic [AP_PADDR_W-1:0] apb_paddr_o,
  output logic [31:0] apb_pwdata_o,
  output logic [3:0] apb_pstrb_o,
  input logic apb_pready_i,
  input logic [31:0] apb_prdata_i,
  input logic apb_pslverr_i
);

  localparam logic [1:0] AXI_RESP_OKAY = 2'b00;
  localparam logic [1:0] AXI_RESP_DECERR = 2'b11;
  localparam logic [1:0] AXI_BURST_INCR = 2'b01;

  typedef enum logic [3:0] {
    AXI_IDLE,
    AXI_W_APB_SETUP_LO,
    AXI_W_APB_ACCESS_LO,
    AXI_W_APB_SETUP_HI,
    AXI_W_APB_ACCESS_HI,
    AXI_W_RESP,
    AXI_R_APB_SETUP_LO,
    AXI_R_APB_ACCESS_LO,
    AXI_R_APB_SETUP_HI,
    AXI_R_APB_ACCESS_HI,
    AXI_R_RESP
  } state_e;

  state_e state_q;
  logic aw_seen_q;
  logic w_seen_q;
  logic [AP_AXI_SLV_ID_W-1:0] id_q;
  logic [AP_PADDR_W-1:0] addr_q;
  logic [63:0] wdata_q;
  logic [7:0] be_q;
  logic bad_q;
  logic err_q;
  logic [31:0] rdata_lo_q;
  logic [31:0] rdata_hi_q;
  logic aw_fire;
  logic w_fire;
  logic ar_fire;
  logic need_lo;
  logic need_hi;

  assign aw_fire = s_axi_i.aw_valid && s_axi_i.aw_ready;
  assign w_fire = s_axi_i.w_valid && s_axi_i.w_ready;
  assign ar_fire = s_axi_i.ar_valid && s_axi_i.ar_ready;
  assign need_lo = |be_q[3:0];
  assign need_hi = |be_q[7:4];

  assign s_axi_i.aw_ready = (state_q == AXI_IDLE) && !aw_seen_q && !w_seen_q;
  assign s_axi_i.w_ready = (state_q == AXI_IDLE) && !w_seen_q &&
                           (aw_seen_q || s_axi_i.aw_valid);
  assign s_axi_i.ar_ready = (state_q == AXI_IDLE) && !aw_seen_q && !w_seen_q &&
                            !s_axi_i.aw_valid && !s_axi_i.w_valid;

  always_comb begin
    apb_psel_o = 1'b0;
    apb_penable_o = 1'b0;
    apb_pwrite_o = 1'b0;
    apb_paddr_o = addr_q;
    apb_pwdata_o = wdata_q[31:0];
    apb_pstrb_o = be_q[3:0];
    unique case (state_q)
      AXI_W_APB_SETUP_LO: begin
        apb_psel_o = 1'b1;
        apb_pwrite_o = 1'b1;
      end
      AXI_W_APB_ACCESS_LO: begin
        apb_psel_o = 1'b1;
        apb_penable_o = 1'b1;
        apb_pwrite_o = 1'b1;
      end
      AXI_W_APB_SETUP_HI: begin
        apb_psel_o = 1'b1;
        apb_pwrite_o = 1'b1;
        apb_paddr_o = addr_q + AP_PADDR_W'(4);
        apb_pwdata_o = wdata_q[63:32];
        apb_pstrb_o = be_q[7:4];
      end
      AXI_W_APB_ACCESS_HI: begin
        apb_psel_o = 1'b1;
        apb_penable_o = 1'b1;
        apb_pwrite_o = 1'b1;
        apb_paddr_o = addr_q + AP_PADDR_W'(4);
        apb_pwdata_o = wdata_q[63:32];
        apb_pstrb_o = be_q[7:4];
      end
      AXI_R_APB_SETUP_LO: begin
        apb_psel_o = 1'b1;
      end
      AXI_R_APB_ACCESS_LO: begin
        apb_psel_o = 1'b1;
        apb_penable_o = 1'b1;
      end
      AXI_R_APB_SETUP_HI: begin
        apb_psel_o = 1'b1;
        apb_paddr_o = addr_q + AP_PADDR_W'(4);
        apb_pstrb_o = be_q[7:4];
      end
      AXI_R_APB_ACCESS_HI: begin
        apb_psel_o = 1'b1;
        apb_penable_o = 1'b1;
        apb_paddr_o = addr_q + AP_PADDR_W'(4);
        apb_pstrb_o = be_q[7:4];
      end
      default: ;
    endcase
  end

  assign s_axi_i.b_id = id_q;
  assign s_axi_i.b_resp = err_q ? AXI_RESP_DECERR : AXI_RESP_OKAY;
  assign s_axi_i.b_user = '0;
  assign s_axi_i.b_valid = state_q == AXI_W_RESP;
  assign s_axi_i.r_id = id_q;
  assign s_axi_i.r_data = {rdata_hi_q, rdata_lo_q};
  assign s_axi_i.r_resp = err_q ? AXI_RESP_DECERR : AXI_RESP_OKAY;
  assign s_axi_i.r_last = 1'b1;
  assign s_axi_i.r_user = '0;
  assign s_axi_i.r_valid = state_q == AXI_R_RESP;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= AXI_IDLE;
      aw_seen_q <= 1'b0;
      w_seen_q <= 1'b0;
      id_q <= '0;
      addr_q <= '0;
      wdata_q <= '0;
      be_q <= '0;
      bad_q <= 1'b0;
      err_q <= 1'b0;
      rdata_lo_q <= '0;
      rdata_hi_q <= '0;
    end else begin
      unique case (state_q)
        AXI_IDLE: begin
          if (aw_fire) begin
            aw_seen_q <= 1'b1;
            id_q <= s_axi_i.aw_id;
            addr_q <= {s_axi_i.aw_addr[AP_PADDR_W-1:3], 3'b000};
            bad_q <= (s_axi_i.aw_len != 8'd0) ||
                     (s_axi_i.aw_size != 3'd3) ||
                     (s_axi_i.aw_burst != AXI_BURST_INCR);
          end
          if (w_fire) begin
            w_seen_q <= 1'b1;
            wdata_q <= s_axi_i.w_data;
            be_q <= s_axi_i.w_strb;
            bad_q <= bad_q || !s_axi_i.w_last;
          end
          if (ar_fire) begin
            id_q <= s_axi_i.ar_id;
            addr_q <= {s_axi_i.ar_addr[AP_PADDR_W-1:3], 3'b000};
            be_q <= 8'hff;
            bad_q <= (s_axi_i.ar_len != 8'd0) ||
                     (s_axi_i.ar_size != 3'd3) ||
                     (s_axi_i.ar_burst != AXI_BURST_INCR);
            err_q <= (s_axi_i.ar_len != 8'd0) ||
                     (s_axi_i.ar_size != 3'd3) ||
                     (s_axi_i.ar_burst != AXI_BURST_INCR);
            rdata_lo_q <= '0;
            rdata_hi_q <= '0;
            state_q <= ((s_axi_i.ar_len != 8'd0) ||
                        (s_axi_i.ar_size != 3'd3) ||
                        (s_axi_i.ar_burst != AXI_BURST_INCR)) ? AXI_R_RESP : AXI_R_APB_SETUP_LO;
          end else if ((aw_seen_q || aw_fire) && (w_seen_q || w_fire)) begin
            err_q <= bad_q || (aw_fire && ((s_axi_i.aw_len != 8'd0) ||
                     (s_axi_i.aw_size != 3'd3) ||
                     (s_axi_i.aw_burst != AXI_BURST_INCR))) ||
                     (w_fire && !s_axi_i.w_last);
            state_q <= (bad_q || (aw_fire && ((s_axi_i.aw_len != 8'd0) ||
                        (s_axi_i.aw_size != 3'd3) ||
                        (s_axi_i.aw_burst != AXI_BURST_INCR))) ||
                        (w_fire && !s_axi_i.w_last)) ? AXI_W_RESP :
                        ((w_fire ? |s_axi_i.w_strb[3:0] : need_lo) ? AXI_W_APB_SETUP_LO : AXI_W_APB_SETUP_HI);
          end
        end
        AXI_W_APB_SETUP_LO:
          state_q <= AXI_W_APB_ACCESS_LO;
        AXI_W_APB_ACCESS_LO:
          if (apb_pready_i) begin
            err_q <= err_q || apb_pslverr_i;
            state_q <= need_hi ? AXI_W_APB_SETUP_HI : AXI_W_RESP;
          end
        AXI_W_APB_SETUP_HI:
          state_q <= AXI_W_APB_ACCESS_HI;
        AXI_W_APB_ACCESS_HI:
          if (apb_pready_i) begin
            err_q <= err_q || apb_pslverr_i;
            state_q <= AXI_W_RESP;
          end
        AXI_W_RESP:
          if (s_axi_i.b_ready) begin
            state_q <= AXI_IDLE;
            aw_seen_q <= 1'b0;
            w_seen_q <= 1'b0;
            bad_q <= 1'b0;
          end
        AXI_R_APB_SETUP_LO:
          state_q <= AXI_R_APB_ACCESS_LO;
        AXI_R_APB_ACCESS_LO:
          if (apb_pready_i) begin
            rdata_lo_q <= apb_prdata_i;
            err_q <= err_q || apb_pslverr_i;
            state_q <= AXI_R_APB_SETUP_HI;
          end
        AXI_R_APB_SETUP_HI:
          state_q <= AXI_R_APB_ACCESS_HI;
        AXI_R_APB_ACCESS_HI:
          if (apb_pready_i) begin
            rdata_hi_q <= apb_prdata_i;
            err_q <= err_q || apb_pslverr_i;
            state_q <= AXI_R_RESP;
          end
        AXI_R_RESP:
          if (s_axi_i.r_ready) begin
            state_q <= AXI_IDLE;
            bad_q <= 1'b0;
          end
        default: state_q <= AXI_IDLE;
      endcase
    end
  end

endmodule
