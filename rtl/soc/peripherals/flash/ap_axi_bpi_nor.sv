// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Read-only AXI4-to-asynchronous-x16-BPI NOR controller. Each halfword read
// uses the BPI ADV# address-latch pulse required by the VCU108 MT28GU01 NOR.
//
// The boot path issues aligned, single-beat 64-bit AXI reads. Each read is
// assembled from four little-endian BPI halfwords. Program/erase commands are
// intentionally not implemented in the first bootable AP revision: writes
// complete with SLVERR and the data bus is never driven by the controller.
module ap_axi_bpi_nor
  import ap_soc_pkg::*;
#(
  parameter logic [AP_PADDR_W-1:0] BASE_ADDR_P = AP_BPI_BASE,
  parameter int unsigned READ_WAIT_CYCLES_P = AP_BPI_READ_WAIT_CYCLES,
  parameter int unsigned ADV_PULSE_CYCLES_P = AP_BPI_ADV_PULSE_CYCLES
) (
  input logic clk,
  input logic rst_n,

  AXI_BUS.Slave s_axi_i,

  output logic [AP_BPI_ADDR_W-1:0] bpi_addr_o,
  inout wire [AP_BPI_DATA_W-1:0] bpi_dq_io,
  output logic bpi_ce_n_o,
  output logic bpi_oe_n_o,
  output logic bpi_we_n_o,
  output logic bpi_adv_n_o,
  output logic bpi_reset_n_o,
  input logic bpi_ryby_n_i
);

  localparam int unsigned AXI_BYTES_P = AP_AXI_DATA_W / 8;
  localparam int unsigned BPI_WORDS_PER_AXI_BEAT_P = AXI_BYTES_P / 2;
  localparam int unsigned HALFWORD_IDX_W_P = $clog2(BPI_WORDS_PER_AXI_BEAT_P);
  localparam int unsigned WAIT_W_P =
      (READ_WAIT_CYCLES_P > 0) ? $clog2(READ_WAIT_CYCLES_P + 1) : 1;
  localparam int unsigned ADV_W_P =
      (ADV_PULSE_CYCLES_P > 1) ? $clog2(ADV_PULSE_CYCLES_P) : 1;
  localparam logic [1:0] AXI_RESP_OKAY = 2'b00;
  localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;
  localparam logic [1:0] AXI_BURST_INCR = 2'b01;
  localparam logic [HALFWORD_IDX_W_P-1:0] LAST_HALFWORD_P =
      HALFWORD_IDX_W_P'(BPI_WORDS_PER_AXI_BEAT_P - 1);

  typedef enum logic [2:0] {
    BPI_IDLE,
    BPI_READ_SETUP,
    BPI_READ_ADV_LOW,
    BPI_READ_WAIT,
    BPI_READ_RESP,
    BPI_WRITE_DATA,
    BPI_WRITE_RESP
  } bpi_state_e;

  bpi_state_e state_q;
  logic [AP_BPI_ADDR_W-1:0] bpi_addr_q;
  logic [HALFWORD_IDX_W_P-1:0] halfword_q;
  logic [WAIT_W_P-1:0] wait_q;
  logic [ADV_W_P-1:0] adv_q;
  logic [AP_AXI_SLV_ID_W-1:0] read_id_q;
  logic [AP_AXI_SLV_ID_W-1:0] write_id_q;
  logic [AP_AXI_DATA_W-1:0] read_data_q;
  logic read_error_q;

  function automatic logic bad_read_attributes();
    return (s_axi_i.ar_len != 8'd0) ||
           (s_axi_i.ar_size != 3'd3) ||
           (s_axi_i.ar_burst != AXI_BURST_INCR) ||
           (s_axi_i.ar_addr[$clog2(AXI_BYTES_P)-1:0] != '0);
  endfunction

  always_comb begin
    s_axi_i.aw_ready = state_q == BPI_IDLE;
    // Do not accept an AR in the same cycle as AW; writes have priority.
    s_axi_i.ar_ready = (state_q == BPI_IDLE) && !s_axi_i.aw_valid;
    s_axi_i.w_ready = state_q == BPI_WRITE_DATA;

    s_axi_i.b_id = write_id_q;
    s_axi_i.b_resp = AXI_RESP_SLVERR;
    s_axi_i.b_user = '0;
    s_axi_i.b_valid = state_q == BPI_WRITE_RESP;

    s_axi_i.r_id = read_id_q;
    s_axi_i.r_data = read_data_q;
    s_axi_i.r_resp = read_error_q ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
    s_axi_i.r_last = 1'b1;
    s_axi_i.r_user = '0;
    s_axi_i.r_valid = state_q == BPI_READ_RESP;

    bpi_addr_o = bpi_addr_q;
    bpi_ce_n_o = 1'b1;
    bpi_oe_n_o = 1'b1;
    bpi_we_n_o = 1'b1;
    bpi_adv_n_o = 1'b1;
    bpi_reset_n_o = rst_n;
    if ((state_q == BPI_READ_SETUP) || (state_q == BPI_READ_ADV_LOW) ||
        (state_q == BPI_READ_WAIT)) begin
      bpi_ce_n_o = 1'b0;
      bpi_oe_n_o = 1'b0;
    end
    if (state_q == BPI_READ_ADV_LOW)
      bpi_adv_n_o = 1'b0;
  end

  // The first revision is read-only. Keep all BPI data pins high-impedance.
  assign bpi_dq_io = {AP_BPI_DATA_W{1'bz}};

  initial begin
    if (AP_AXI_DATA_W != 64 || AP_BPI_DATA_W != 16 ||
        BPI_WORDS_PER_AXI_BEAT_P != 4)
      $fatal(1, "ap_axi_bpi_nor: AP boot controller requires 64-bit AXI and x16 BPI");
    if (ADV_PULSE_CYCLES_P == 0)
      $fatal(1, "ap_axi_bpi_nor: ADV_PULSE_CYCLES_P must be at least one");
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= BPI_IDLE;
      bpi_addr_q <= '0;
      halfword_q <= '0;
      wait_q <= '0;
      adv_q <= '0;
      read_id_q <= '0;
      write_id_q <= '0;
      read_data_q <= '0;
      read_error_q <= 1'b0;
    end else begin
      unique case (state_q)
        BPI_IDLE: begin
          if (s_axi_i.aw_valid && s_axi_i.aw_ready) begin
            write_id_q <= s_axi_i.aw_id;
            state_q <= BPI_WRITE_DATA;
          end else if (s_axi_i.ar_valid && s_axi_i.ar_ready) begin
            read_id_q <= s_axi_i.ar_id;
            read_data_q <= '0;
            read_error_q <= bad_read_attributes();
            if (bad_read_attributes()) begin
              state_q <= BPI_READ_RESP;
            end else begin
              bpi_addr_q <= AP_BPI_ADDR_W'((s_axi_i.ar_addr - BASE_ADDR_P) >> 1);
              halfword_q <= '0;
              state_q <= BPI_READ_SETUP;
            end
          end
        end

        // Keep CE#/OE# and the new address stable before ADV# rises. This
        // separates the source clock edge that changes address from the BPI
        // latch pulse, which is necessary at the MIG 300 MHz UI frequency.
        BPI_READ_SETUP: begin
          adv_q <= ADV_W_P'(ADV_PULSE_CYCLES_P - 1);
          state_q <= BPI_READ_ADV_LOW;
        end

        BPI_READ_ADV_LOW: begin
          if (adv_q != '0) begin
            adv_q <= adv_q - 1'b1;
          end else begin
            wait_q <= WAIT_W_P'(READ_WAIT_CYCLES_P);
            state_q <= BPI_READ_WAIT;
          end
        end

        BPI_READ_WAIT: begin
          if (wait_q != '0) begin
            wait_q <= wait_q - 1'b1;
          end else if (bpi_ryby_n_i) begin
            read_data_q[halfword_q * AP_BPI_DATA_W +: AP_BPI_DATA_W] <= bpi_dq_io;
            if (halfword_q == LAST_HALFWORD_P) begin
              state_q <= BPI_READ_RESP;
            end else begin
              halfword_q <= halfword_q + 1'b1;
              bpi_addr_q <= bpi_addr_q + 1'b1;
              state_q <= BPI_READ_SETUP;
            end
          end
        end

        BPI_READ_RESP:
          if (s_axi_i.r_valid && s_axi_i.r_ready)
            state_q <= BPI_IDLE;

        BPI_WRITE_DATA:
          if (s_axi_i.w_valid && s_axi_i.w_ready)
            state_q <= BPI_WRITE_RESP;

        BPI_WRITE_RESP:
          if (s_axi_i.b_valid && s_axi_i.b_ready)
            state_q <= BPI_IDLE;

        default: state_q <= BPI_IDLE;
      endcase
    end
  end

endmodule
