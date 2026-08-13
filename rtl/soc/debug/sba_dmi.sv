// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Minimal Debug 1.0 System Bus Access (SBA) DMI slave.
//
// The SoC owns address decoding and completes requests asynchronously through
// the sba_* interface.  SBCS exposes 32-bit accesses; unsupported access sizes
// report sberror=2 without issuing a bus transaction.
module sba_dmi #(
  parameter int DMI_ADDR_WIDTH = 7
) (
  // System clock and reset
  input  logic                      clk,
  input  logic                      rst_n,

  // DMI request/response transaction
  input  logic                      dmi_req_valid_i,
  input  logic [DMI_ADDR_WIDTH-1:0] dmi_req_addr_i,
  input  logic [31:0]               dmi_req_wdata_i,
  input  logic [1:0]                dmi_req_op_i,
  output logic                      dmi_req_selected_o,
  output logic                      dmi_resp_valid_o,
  output logic [31:0]               dmi_resp_rdata_o,
  output logic [1:0]                dmi_resp_op_o,

  // System-bus access request/response transaction
  output logic                      sba_req_o,
  output logic                      sba_we_o,
  output logic [31:0]               sba_addr_o,
  output logic [31:0]               sba_wdata_o,
  output logic [3:0]                sba_be_o,
  input  logic                      sba_resp_valid_i,
  input  logic [31:0]               sba_rdata_i,
  input  logic                      sba_err_i
);
  // DMI register addresses and protocol encodings
  localparam logic [DMI_ADDR_WIDTH-1:0] REG_SBCS      = 7'h38;
  localparam logic [DMI_ADDR_WIDTH-1:0] REG_SBADDRESS = 7'h39;
  localparam logic [DMI_ADDR_WIDTH-1:0] REG_SBDATA0   = 7'h3c;
  localparam logic [1:0] DMI_OP_READ = 2'b01;
  localparam logic [1:0] DMI_OP_WRITE = 2'b10;
  localparam logic [1:0] DMI_RESP_OK = 2'b00;
  localparam logic [1:0] DMI_RESP_ERR = 2'b10;

  // SBA architectural register state
  logic [31:0] sbaddress_q;
  logic [31:0] sbdata_q;
  logic        sbbusy_q;
  logic [2:0]  sberror_q;
  logic [2:0]  sbaccess_q;

  assign dmi_req_selected_o = dmi_req_valid_i &&
                              ((dmi_req_addr_i == REG_SBCS) ||
                               (dmi_req_addr_i == REG_SBADDRESS) ||
                               (dmi_req_addr_i == REG_SBDATA0));
  assign sba_addr_o = sbaddress_q;
  assign sba_wdata_o = sbdata_q;
  assign sba_be_o = 4'hf;

  always_comb begin
    dmi_resp_valid_o = dmi_req_selected_o;
    dmi_resp_op_o = DMI_RESP_OK;
    dmi_resp_rdata_o = 32'h0000_0000;
    if (dmi_req_selected_o && (dmi_req_op_i == DMI_OP_READ)) begin
      unique case (dmi_req_addr_i)
        REG_SBCS: begin
          dmi_resp_rdata_o[31:29] = 3'd1; // sbversion=1
          dmi_resp_rdata_o[22] = sbbusy_q;
          dmi_resp_rdata_o[20] = 1'b1; // 32-bit access supported
          dmi_resp_rdata_o[19:17] = sbaccess_q;
          dmi_resp_rdata_o[14:12] = sberror_q;
        end
        REG_SBADDRESS: dmi_resp_rdata_o = sbaddress_q;
        REG_SBDATA0: dmi_resp_rdata_o = sbdata_q;
        default: dmi_resp_op_o = DMI_RESP_ERR;
      endcase
    end else if (dmi_req_selected_o && (dmi_req_op_i != DMI_OP_WRITE)) begin
      dmi_resp_op_o = DMI_RESP_ERR;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sbaddress_q <= 32'h0000_0000;
      sbdata_q <= 32'h0000_0000;
      sbbusy_q <= 1'b0;
      sberror_q <= 3'd0;
      sbaccess_q <= 3'd2;
      sba_req_o <= 1'b0;
      sba_we_o <= 1'b0;
    end else begin
      sba_req_o <= 1'b0;
      if (sba_resp_valid_i && sbbusy_q) begin
        sbbusy_q <= 1'b0;
        if (sba_err_i)
          sberror_q <= 3'd2;
        else if (!sba_we_o)
          sbdata_q <= sba_rdata_i;
      end
      if (dmi_req_selected_o && (dmi_req_op_i == DMI_OP_WRITE)) begin
        unique case (dmi_req_addr_i)
          REG_SBCS: begin
            sbaccess_q <= dmi_req_wdata_i[19:17];
            if (dmi_req_wdata_i[14:12] != 3'd0) sberror_q <= 3'd0;
          end
          REG_SBADDRESS: sbaddress_q <= dmi_req_wdata_i;
          REG_SBDATA0: begin
            sbdata_q <= dmi_req_wdata_i;
            if (sbbusy_q) begin
              sberror_q <= 3'd1;
            end else if (sbaccess_q != 3'd2) begin
              sberror_q <= 3'd2;
            end else begin
              sbbusy_q <= 1'b1;
              sba_we_o <= 1'b1;
              sba_req_o <= 1'b1;
            end
          end
          default: ;
        endcase
      end else if (dmi_req_selected_o && (dmi_req_op_i == DMI_OP_READ) &&
                   (dmi_req_addr_i == REG_SBDATA0) && !sbbusy_q) begin
        if (sbaccess_q != 3'd2) begin
          sberror_q <= 3'd2;
        end else begin
          sbbusy_q <= 1'b1;
          sba_we_o <= 1'b0;
          sba_req_o <= 1'b1;
        end
      end
    end
  end
endmodule
