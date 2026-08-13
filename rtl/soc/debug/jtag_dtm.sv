// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

module jtag_dtm #(
  parameter int DMI_ADDR_WIDTH = 7,
  parameter int IR_WIDTH = 5
) (
  // JTAG TAP pins
  input  logic                       tck_i,
  input  logic                       trst_n_i,
  input  logic                       tms_i,
  input  logic                       tdi_i,
  output logic                       tdo_o,

  // Toggle-based DMI request/response transport
  output logic                       dmi_req_toggle_o,
  output logic [DMI_ADDR_WIDTH-1:0]  dmi_req_addr_o,
  output logic [31:0]                dmi_req_wdata_o,
  output logic [1:0]                 dmi_req_op_o,
  input  logic                       dmi_resp_toggle_i,
  input  logic [31:0]                dmi_resp_rdata_i,
  input  logic [1:0]                 dmi_resp_op_i
);

  // JTAG scan-register sizing and instruction encodings
  localparam int DMI_SCAN_WIDTH = DMI_ADDR_WIDTH + 32 + 2;

  localparam logic [IR_WIDTH-1:0] IR_IDCODE = 5'h01;
  localparam logic [IR_WIDTH-1:0] IR_DTMCS  = 5'h10;
  localparam logic [IR_WIDTH-1:0] IR_DMI    = 5'h11;
  localparam logic [IR_WIDTH-1:0] IR_BYPASS = 5'h1f;

  // TAP state machine
  typedef enum logic [3:0] {
    TL_RESET  = 4'd0,
    RUN_IDLE  = 4'd1,
    SEL_DR    = 4'd2,
    CAP_DR    = 4'd3,
    SHIFT_DR  = 4'd4,
    EXIT1_DR  = 4'd5,
    PAUSE_DR  = 4'd6,
    EXIT2_DR  = 4'd7,
    UPDATE_DR = 4'd8,
    SEL_IR    = 4'd9,
    CAP_IR    = 4'd10,
    SHIFT_IR  = 4'd11,
    EXIT1_IR  = 4'd12,
    PAUSE_IR  = 4'd13,
    EXIT2_IR  = 4'd14,
    UPDATE_IR = 4'd15
  } tap_state_e;

  // TAP shift state and synchronised DMI response
  tap_state_e state_q;
  logic [IR_WIDTH-1:0] ir_q;
  logic [63:0] shift_q;
  int unsigned shift_count_q;
  logic resp_toggle_meta_q;
  logic resp_toggle_sync_q;
  logic resp_toggle_seen_q;
  logic [31:0] dmi_resp_rdata_q;
  logic [1:0] dmi_resp_op_q;

  function automatic tap_state_e next_state(input tap_state_e state, input logic tms);
    case (state)
      TL_RESET:  next_state = tms ? TL_RESET : RUN_IDLE;
      RUN_IDLE:  next_state = tms ? SEL_DR : RUN_IDLE;
      SEL_DR:    next_state = tms ? SEL_IR : CAP_DR;
      CAP_DR:    next_state = tms ? EXIT1_DR : SHIFT_DR;
      SHIFT_DR:  next_state = tms ? EXIT1_DR : SHIFT_DR;
      EXIT1_DR:  next_state = tms ? UPDATE_DR : PAUSE_DR;
      PAUSE_DR:  next_state = tms ? EXIT2_DR : PAUSE_DR;
      EXIT2_DR:  next_state = tms ? UPDATE_DR : SHIFT_DR;
      UPDATE_DR: next_state = tms ? SEL_DR : RUN_IDLE;
      SEL_IR:    next_state = tms ? TL_RESET : CAP_IR;
      CAP_IR:    next_state = tms ? EXIT1_IR : SHIFT_IR;
      SHIFT_IR:  next_state = tms ? EXIT1_IR : SHIFT_IR;
      EXIT1_IR:  next_state = tms ? UPDATE_IR : PAUSE_IR;
      PAUSE_IR:  next_state = tms ? EXIT2_IR : PAUSE_IR;
      EXIT2_IR:  next_state = tms ? UPDATE_IR : SHIFT_IR;
      UPDATE_IR: next_state = tms ? SEL_DR : RUN_IDLE;
      default:   next_state = TL_RESET;
    endcase
  endfunction

  assign tdo_o = (((state_q == SHIFT_IR) || (state_q == SHIFT_DR)) && (shift_count_q < 64)) ?
                 shift_q[shift_count_q] : 1'b0;

  always_ff @(posedge tck_i or negedge trst_n_i) begin
    if (!trst_n_i) begin
      state_q <= TL_RESET;
      ir_q <= IR_IDCODE;
      shift_q <= '0;
      shift_count_q <= 0;
      dmi_req_toggle_o <= 1'b0;
      dmi_req_addr_o <= '0;
      dmi_req_wdata_o <= 32'h0000_0000;
      dmi_req_op_o <= 2'b00;
      resp_toggle_meta_q <= 1'b0;
      resp_toggle_sync_q <= 1'b0;
      resp_toggle_seen_q <= 1'b0;
      dmi_resp_rdata_q <= 32'h0000_0000;
      dmi_resp_op_q <= 2'b00;
    end else begin
      tap_state_e state_d;
      state_d = next_state(state_q, tms_i);

      resp_toggle_meta_q <= dmi_resp_toggle_i;
      resp_toggle_sync_q <= resp_toggle_meta_q;
      if (resp_toggle_sync_q != resp_toggle_seen_q) begin
        resp_toggle_seen_q <= resp_toggle_sync_q;
        dmi_resp_rdata_q <= dmi_resp_rdata_i;
        dmi_resp_op_q <= dmi_resp_op_i;
      end

      if (state_d == CAP_IR) begin
        shift_q <= {{(64-IR_WIDTH){1'b0}}, ir_q};
        shift_count_q <= 0;
      end else if (state_q == SHIFT_IR) begin
        if (shift_count_q < IR_WIDTH) begin
          shift_q[shift_count_q] <= tdi_i;
          shift_count_q <= shift_count_q + 1;
        end
      end

      if (state_d == CAP_DR) begin
        shift_count_q <= 0;
        unique case (ir_q)
          IR_IDCODE: shift_q <= 64'h0000_0000_1357_11db;
          IR_DTMCS:  shift_q <= 64'h0000_0000_0000_0071; // version=1, abits=7.
          IR_DMI:    shift_q <= {{(64-DMI_SCAN_WIDTH){1'b0}}, dmi_req_addr_o, dmi_resp_rdata_q, dmi_resp_op_q};
          default:   shift_q <= 64'h1;
        endcase
      end else if (state_q == SHIFT_DR) begin
        if (shift_count_q < 64) begin
          shift_q[shift_count_q] <= tdi_i;
          shift_count_q <= shift_count_q + 1;
        end
      end

      if (state_d == UPDATE_IR) begin
        ir_q <= shift_q[IR_WIDTH-1:0];
      end

      if ((state_d == UPDATE_DR) && (ir_q == IR_DMI) && (shift_count_q >= DMI_SCAN_WIDTH)) begin
        dmi_req_op_o <= shift_q[1:0];
        dmi_req_wdata_o <= shift_q[33:2];
        dmi_req_addr_o <= shift_q[33 + DMI_ADDR_WIDTH:34];
        if (shift_q[1:0] != 2'b00) begin
          dmi_req_toggle_o <= ~dmi_req_toggle_o;
        end
      end

      state_q <= state_d;
    end
  end
endmodule
