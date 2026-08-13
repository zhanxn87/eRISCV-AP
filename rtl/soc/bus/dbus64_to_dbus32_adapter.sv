// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// RV64 core D-bus boundary adapter for the legacy 32-bit SoC fabric.
// A core request is completed only after every selected 32-bit word has
// completed. Addresses above the current 4 GiB legacy map fail explicitly;
// they are never truncated into a different device window.
module dbus64_to_dbus32_adapter #(
  parameter int unsigned PADDR_W_P = 48
) (
  input  logic                   clk,
  input  logic                   rst_n,

  input  logic                   dbus_req_i,
  input  logic [PADDR_W_P-1:0]   dbus_addr_i,
  input  logic [63:0]            dbus_wdata_i,
  input  logic                   dbus_we_i,
  input  logic [7:0]             dbus_be_i,
  output logic                   dbus_resp_valid_o,
  output logic [63:0]            dbus_rdata_o,
  output logic                   dbus_err_o,

  output logic                   legacy_req_o,
  output logic [31:0]            legacy_addr_o,
  output logic [31:0]            legacy_wdata_o,
  output logic                   legacy_we_o,
  output logic [3:0]             legacy_be_o,
  input  logic                   legacy_resp_valid_i,
  input  logic [31:0]            legacy_rdata_i,
  input  logic                   legacy_err_i
);

  typedef enum logic [2:0] {
    ADAPTER_IDLE,
    ADAPTER_FIRST_WAIT,
    ADAPTER_SECOND_ISSUE,
    ADAPTER_SECOND_WAIT,
    ADAPTER_RESP
  } adapter_state_e;

  adapter_state_e state_q;
  logic [31:0] addr_q;
  logic [63:0] wdata_q;
  logic        we_q;
  logic [7:0]  be_q;
  logic        first_high_q;
  logic [63:0] rdata_q;
  logic        err_q;

  logic [7:0]  incoming_be;
  logic        incoming_low;
  logic        incoming_high;
  logic        incoming_first_high;
  logic        incoming_second;
  logic [31:0] incoming_base_addr;
  logic        incoming_high_addr;

  // A zero read strobe was the RV32 contract. Retain a conservative 64-bit
  // read for external users of that old contract; RV64 mem_stage supplies the
  // exact load byte mask.
  assign incoming_be = (dbus_be_i == 8'h00) ? 8'hff : dbus_be_i;
  assign incoming_low = |incoming_be[3:0];
  assign incoming_high = |incoming_be[7:4];
  assign incoming_first_high = !incoming_low && incoming_high;
  assign incoming_second = incoming_low && incoming_high;
  assign incoming_base_addr = {dbus_addr_i[31:3], 3'b000};
  assign incoming_high_addr = |dbus_addr_i[PADDR_W_P-1:32];

  always_comb begin
    legacy_req_o = 1'b0;
    legacy_addr_o = '0;
    legacy_wdata_o = '0;
    legacy_we_o = 1'b0;
    legacy_be_o = '0;

    if ((state_q == ADAPTER_IDLE) && dbus_req_i && !incoming_high_addr) begin
      legacy_req_o = 1'b1;
      legacy_addr_o = incoming_base_addr + (incoming_first_high ? 32'd4 : 32'd0);
      legacy_wdata_o = incoming_first_high ? dbus_wdata_i[63:32] : dbus_wdata_i[31:0];
      legacy_we_o = dbus_we_i;
      legacy_be_o = incoming_first_high ? incoming_be[7:4] : incoming_be[3:0];
    end else if (state_q == ADAPTER_SECOND_ISSUE) begin
      legacy_req_o = 1'b1;
      legacy_addr_o = addr_q + 32'd4;
      legacy_wdata_o = wdata_q[63:32];
      legacy_we_o = we_q;
      legacy_be_o = be_q[7:4];
    end
  end

  assign dbus_resp_valid_o = state_q == ADAPTER_RESP;
  assign dbus_rdata_o = rdata_q;
  assign dbus_err_o = err_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ADAPTER_IDLE;
      addr_q <= '0;
      wdata_q <= '0;
      we_q <= 1'b0;
      be_q <= '0;
      first_high_q <= 1'b0;
      rdata_q <= '0;
      err_q <= 1'b0;
    end else begin
      unique case (state_q)
        ADAPTER_IDLE: begin
          if (dbus_req_i) begin
            rdata_q <= '0;
            err_q <= 1'b0;
            if (incoming_high_addr) begin
              err_q <= 1'b1;
              state_q <= ADAPTER_RESP;
            end else begin
              addr_q <= incoming_base_addr;
              wdata_q <= dbus_wdata_i;
              we_q <= dbus_we_i;
              be_q <= incoming_be;
              first_high_q <= incoming_first_high;
              if (legacy_resp_valid_i) begin
                if (incoming_first_high)
                  rdata_q[63:32] <= legacy_rdata_i;
                else
                  rdata_q[31:0] <= legacy_rdata_i;
                err_q <= legacy_err_i;
                state_q <= incoming_second ? ADAPTER_SECOND_ISSUE : ADAPTER_RESP;
              end else begin
                state_q <= ADAPTER_FIRST_WAIT;
              end
            end
          end
        end

        ADAPTER_FIRST_WAIT: begin
          if (legacy_resp_valid_i) begin
            if (first_high_q)
              rdata_q[63:32] <= legacy_rdata_i;
            else
              rdata_q[31:0] <= legacy_rdata_i;
            err_q <= err_q | legacy_err_i;
            state_q <= (|be_q[3:0] && |be_q[7:4]) ?
                       ADAPTER_SECOND_ISSUE : ADAPTER_RESP;
          end
        end

        ADAPTER_SECOND_ISSUE: begin
          if (legacy_resp_valid_i) begin
            rdata_q[63:32] <= legacy_rdata_i;
            err_q <= err_q | legacy_err_i;
            state_q <= ADAPTER_RESP;
          end else begin
            state_q <= ADAPTER_SECOND_WAIT;
          end
        end

        ADAPTER_SECOND_WAIT: begin
          if (legacy_resp_valid_i) begin
            rdata_q[63:32] <= legacy_rdata_i;
            err_q <= err_q | legacy_err_i;
            state_q <= ADAPTER_RESP;
          end
        end

        ADAPTER_RESP: state_q <= ADAPTER_IDLE;
        default: state_q <= ADAPTER_IDLE;
      endcase
    end
  end

endmodule
