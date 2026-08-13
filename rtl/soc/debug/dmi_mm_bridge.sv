// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Memory-mapped to DMI bridge — replaces JTAG DTM for simulation.
//
// Maps a simple bus transaction to a DMI (Debug Module Interface) request.
// The DMI protocol uses: addr[6:0], op[1:0] (0=NOP, 1=READ, 2=WRITE), data[31:0]
//
// Memory map (relative to BASE):
//   0x00: DMI request  — write: {addr[6:0], op[1:0], 23'd0, data_reg} triggers DMI
//   0x04: DMI status   — read: [0]=busy, [1]=error
//   0x08: DMI rdata    — read: DMI response data
//   0x0C: DMI wdata    — write: sets write-data register
module dmi_mm_bridge #(
  parameter int          DMI_ADDR_WIDTH = 7,
  parameter logic [31:0] BASE_ADDR      = 32'h1A00_0000
) (
  // System clock and reset
  input  logic        clk,
  input  logic        rst_n,

  // Memory-mapped DBus transaction
  input  logic        req_i,
  input  logic        we_i,
  input  logic [3:0]  be_i,
  input  logic [31:0] addr_i,
  input  logic [31:0] wdata_i,
  output logic        hit_o,
  output logic        resp_valid_o,
  output logic [31:0] rdata_o,
  output logic        err_o,

  // DMI request/response transaction to debug module
  output logic                      dmi_req_valid_o,
  output logic [DMI_ADDR_WIDTH-1:0] dmi_req_addr_o,
  output logic [31:0]               dmi_req_wdata_o,
  output logic [1:0]                dmi_req_op_o,
  input  logic                      dmi_resp_valid_i,
  input  logic [31:0]               dmi_resp_rdata_i,
  input  logic [1:0]                dmi_resp_op_i
);

  // Local register offsets
  localparam logic [31:0] OFFSET_REQ   = 32'h00;
  localparam logic [31:0] OFFSET_STAT  = 32'h04;
  localparam logic [31:0] OFFSET_RDATA = 32'h08;
  localparam logic [31:0] OFFSET_WDATA = 32'h0C;

  // Address decode and request state
  logic [31:0] local_addr;
  logic        in_range;

  logic [31:0] wdata_q;
  logic        busy_q;
  logic        error_q;
  logic        req_sent_q;

  assign local_addr = addr_i - BASE_ADDR;
  assign in_range   = (addr_i >= BASE_ADDR) && (addr_i < (BASE_ADDR + 32'h1000));
  assign hit_o      = in_range;
  assign err_o      = 1'b0;

  always_comb begin
    rdata_o       = '0;
    if (in_range) begin
      case (local_addr[3:2])
        2'd0: rdata_o = {19'd0, busy_q, 12'd0};       // OFFSET_REQ read = status
        2'd1: rdata_o = {30'd0, error_q, busy_q};      // OFFSET_STAT
        2'd2: rdata_o = dmi_resp_rdata_i;              // OFFSET_RDATA
        2'd3: rdata_o = wdata_q;                       // OFFSET_WDATA readback
      endcase
    end
  end

  // DMI request: routed directly from registered fields (no combinational assign)

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wdata_q         <= '0;
      busy_q          <= 1'b0;
      error_q         <= 1'b0;
      req_sent_q      <= 1'b0;
      dmi_req_valid_o <= 1'b0;
      dmi_req_addr_o  <= '0;
      dmi_req_wdata_o <= '0;
      dmi_req_op_o    <= 2'b00;
      resp_valid_o    <= 1'b0;
    end else begin
      dmi_req_valid_o <= 1'b0;
      dmi_req_addr_o  <= dmi_req_addr_o;   // hold
      dmi_req_wdata_o <= dmi_req_wdata_o;  // hold
      dmi_req_op_o    <= dmi_req_op_o;     // hold
      resp_valid_o    <= 1'b0;

      if (req_i && in_range && we_i) begin
        case (local_addr[3:2])
          2'd0: begin  // Trigger DMI request
            wdata_q <= wdata_i;
            if (!busy_q) begin
              dmi_req_valid_o <= 1'b1;
              dmi_req_addr_o  <= wdata_i[6:0];
              dmi_req_op_o    <= wdata_i[9:8];
              dmi_req_wdata_o <= wdata_i;
              busy_q    <= 1'b1;
              error_q   <= 1'b0;
              req_sent_q <= 1'b1;
              resp_valid_o <= 1'b1;
            end
          end
          2'd3: begin  // Write wdata register
            wdata_q <= wdata_i;
            resp_valid_o <= 1'b1;
          end
          default: resp_valid_o <= 1'b1;
        endcase
      end

      if (req_i && in_range && !we_i) begin
        resp_valid_o <= 1'b1;
      end

      // DMI response handling
      if (dmi_resp_valid_i && req_sent_q) begin
        busy_q     <= 1'b0;
        req_sent_q <= 1'b0;
        if (dmi_resp_op_i == 2'b10) begin
          error_q <= 1'b1;
        end
      end
    end
  end

endmodule
