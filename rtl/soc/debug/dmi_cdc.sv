// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

module dmi_cdc #(
  parameter int DMI_ADDR_WIDTH = 7
) (
  // System clock and reset
  input  logic                      clk,
  input  logic                      rst_n,

  // TCK-domain toggle request/response transport
  input  logic                      dmi_req_toggle_tck_i,
  input  logic [DMI_ADDR_WIDTH-1:0] dmi_req_addr_tck_i,
  input  logic [31:0]               dmi_req_wdata_tck_i,
  input  logic [1:0]                dmi_req_op_tck_i,
  output logic                      dmi_resp_toggle_tck_o,
  output logic [31:0]               dmi_resp_rdata_tck_o,
  output logic [1:0]                dmi_resp_op_tck_o,

  // System-domain debug-module request/response transport
  output logic                      dm_req_valid_o,
  output logic [DMI_ADDR_WIDTH-1:0] dm_req_addr_o,
  output logic [31:0]               dm_req_wdata_o,
  output logic [1:0]                dm_req_op_o,
  input  logic                      dm_resp_valid_i,
  input  logic [31:0]               dm_resp_rdata_i,
  input  logic [1:0]                dm_resp_op_i
);

  // Request/response ownership state
  typedef enum logic [1:0] {
    IDLE,
    ISSUE,
    RESPOND
  } state_e;

  state_e state_q;
  // Synchronised TCK request toggle
  logic req_toggle_meta_q;
  logic req_toggle_sync_q;
  logic req_toggle_seen_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= IDLE;
      req_toggle_meta_q <= 1'b0;
      req_toggle_sync_q <= 1'b0;
      req_toggle_seen_q <= 1'b0;
      dm_req_valid_o <= 1'b0;
      dm_req_addr_o <= '0;
      dm_req_wdata_o <= 32'h0000_0000;
      dm_req_op_o <= 2'b00;
      dmi_resp_toggle_tck_o <= 1'b0;
      dmi_resp_rdata_tck_o <= 32'h0000_0000;
      dmi_resp_op_tck_o <= 2'b00;
    end else begin
      req_toggle_meta_q <= dmi_req_toggle_tck_i;
      req_toggle_sync_q <= req_toggle_meta_q;
      dm_req_valid_o <= 1'b0;

      unique case (state_q)
        IDLE: begin
          if (req_toggle_sync_q != req_toggle_seen_q) begin
            req_toggle_seen_q <= req_toggle_sync_q;
            dm_req_addr_o <= dmi_req_addr_tck_i;
            dm_req_wdata_o <= dmi_req_wdata_tck_i;
            dm_req_op_o <= dmi_req_op_tck_i;
            state_q <= ISSUE;
          end
        end
        ISSUE: begin
          dm_req_valid_o <= 1'b1;
          state_q <= RESPOND;
        end
        RESPOND: begin
          if (dm_resp_valid_i) begin
            dmi_resp_rdata_tck_o <= dm_resp_rdata_i;
            dmi_resp_op_tck_o <= dm_resp_op_i;
            dmi_resp_toggle_tck_o <= ~dmi_resp_toggle_tck_o;
            state_q <= IDLE;
          end
        end
        default: state_q <= IDLE;
      endcase
    end
  end
endmodule
