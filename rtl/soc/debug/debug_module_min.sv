// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

module debug_module_min #(
  parameter int DMI_ADDR_WIDTH = 7
) (
  // Clock/reset
  input  logic                      clk,
  input  logic                      rst_n,

  // DMI request/response
  input  logic                      dmi_req_valid_i,
  input  logic [DMI_ADDR_WIDTH-1:0] dmi_req_addr_i,
  input  logic [31:0]               dmi_req_wdata_i,
  input  logic [1:0]                dmi_req_op_i,
  output logic                      dmi_resp_valid_o,
  output logic [31:0]               dmi_resp_rdata_o,
  output logic [1:0]                dmi_resp_op_o,

  // Hart run-state
  output logic                      hart_halt_req_o,
  output logic                      hart_resume_req_o,
  input  logic                      hart_halted_i,
  input  logic                      hart_running_i,
  input  logic [63:0]               hart_pc_i,
  input  logic [2:0]                hart_cause_i,

  // Abstract register access
  output logic                      debug_reg_req_valid_o,
  output logic                      debug_reg_write_o,
  output logic [15:0]               debug_reg_addr_o,
  output logic [63:0]               debug_reg_wdata_o,
  input  logic [63:0]               debug_reg_rdata_i,
  input  logic                      debug_reg_error_i
);

  // DMI register addresses
  localparam logic [DMI_ADDR_WIDTH-1:0] REG_DATA0      = 7'h04;
  localparam logic [DMI_ADDR_WIDTH-1:0] REG_DATA1      = 7'h05;
  localparam logic [DMI_ADDR_WIDTH-1:0] REG_DMCONTROL  = 7'h10;
  localparam logic [DMI_ADDR_WIDTH-1:0] REG_DMSTATUS   = 7'h11;
  localparam logic [DMI_ADDR_WIDTH-1:0] REG_HARTINFO   = 7'h12;
  localparam logic [DMI_ADDR_WIDTH-1:0] REG_ABSTRACTCS = 7'h16;
  localparam logic [DMI_ADDR_WIDTH-1:0] REG_COMMAND    = 7'h17;
  localparam logic [DMI_ADDR_WIDTH-1:0] REG_HALTSUM0   = 7'h40;

  // DMI operation and response encodings
  localparam logic [1:0] DMI_OP_NOP   = 2'b00;
  localparam logic [1:0] DMI_OP_READ  = 2'b01;
  localparam logic [1:0] DMI_OP_WRITE = 2'b10;
  localparam logic [1:0] DMI_RESP_OK  = 2'b00;
  localparam logic [1:0] DMI_RESP_ERR = 2'b10;

  // Abstract-command error encodings
  localparam logic [2:0] CMDERR_NONE        = 3'd0;
  localparam logic [2:0] CMDERR_NOTSUP      = 3'd2;
  localparam logic [2:0] CMDERR_EXCEPTION   = 3'd3;
  localparam logic [2:0] CMDERR_HALTRESUME  = 3'd4;

  // Debug-module architectural state
  logic dmactive_q;
  logic haltreq_q;
  logic resumeack_q;
  logic havereset_q;
  logic [31:0] data0_q;
  logic [31:0] data1_q;
  logic [2:0]  cmderr_q;

  // Decoded abstract-command fields and status
  logic command_write;
  logic command_supported;
  logic command_hart_ready;
  logic command_reg_error;
  logic [2:0] command_aarsize;
  logic       command_transfer;
  logic       command_write_reg;
  logic       command_postexec;
  logic       command_postincrement;
  logic [15:0] command_regno;

  assign command_write = dmi_req_valid_i && (dmi_req_op_i == DMI_OP_WRITE) &&
                         (dmi_req_addr_i == REG_COMMAND);
  assign command_aarsize = dmi_req_wdata_i[22:20];
  assign command_postincrement = dmi_req_wdata_i[19];
  assign command_postexec = dmi_req_wdata_i[18];
  assign command_transfer = dmi_req_wdata_i[17];
  assign command_write_reg = dmi_req_wdata_i[16];
  assign command_regno = dmi_req_wdata_i[15:0];
  assign command_supported = (dmi_req_wdata_i[31:24] == 8'h00) &&
                             (command_aarsize == 3'd3) &&
                             command_transfer &&
                             !command_postexec &&
                             !command_postincrement;
  assign command_hart_ready = dmactive_q && hart_halted_i;
  assign command_reg_error = debug_reg_error_i;

  assign debug_reg_req_valid_o = command_write && command_supported && command_hart_ready &&
                                 (cmderr_q == CMDERR_NONE);
  assign debug_reg_write_o = command_write_reg;
  assign debug_reg_addr_o = command_regno;
  assign debug_reg_wdata_o = {data1_q, data0_q};

  function automatic logic [31:0] dmstatus_value;
    logic [31:0] value;
    begin
      value = 32'h0000_0003; // version=3 target: Debug 1.0-style minimal DM.
      value[7] = 1'b1;       // authenticated
      value[6] = 1'b0;       // authbusy: no authentication flow is active
      value[5] = 1'b0;       // hasresethaltreq: optional feature not implemented
      value[8] = hart_halted_i;
      value[9] = hart_halted_i;
      value[10] = hart_running_i;
      value[11] = hart_running_i;
      value[16] = resumeack_q;
      value[17] = resumeack_q;
      value[18] = havereset_q;
      value[19] = havereset_q;
      dmstatus_value = value;
    end
  endfunction

  function automatic logic [31:0] abstractcs_value;
    logic [31:0] value;
    begin
      value = 32'h0000_0000;
      value[28:24] = 5'd0;      // no program buffer
      value[12] = 1'b0;         // single-cycle command engine is never busy
      value[10:8] = cmderr_q;
      value[3:0] = 4'd2;        // data0 and data1 are implemented
      abstractcs_value = value;
    end
  endfunction

  always_comb begin
    dmi_resp_valid_o = dmi_req_valid_i;
    dmi_resp_op_o = DMI_RESP_OK;
    dmi_resp_rdata_o = 32'h0000_0000;

    if (dmi_req_valid_i && (dmi_req_op_i == DMI_OP_READ)) begin
      unique case (dmi_req_addr_i)
        REG_DATA0:      dmi_resp_rdata_o = data0_q;
        REG_DATA1:      dmi_resp_rdata_o = data1_q;
        REG_DMCONTROL:  dmi_resp_rdata_o = {haltreq_q, 30'd0, dmactive_q};
        REG_DMSTATUS:   dmi_resp_rdata_o = dmstatus_value();
        REG_HARTINFO:   dmi_resp_rdata_o = 32'h0000_0001;
        REG_ABSTRACTCS: dmi_resp_rdata_o = abstractcs_value();
        REG_COMMAND:    dmi_resp_rdata_o = 32'h0000_0000;
        REG_HALTSUM0:   dmi_resp_rdata_o = {31'd0, hart_halted_i};
        default: begin
          dmi_resp_rdata_o = 32'h0000_0000;
          dmi_resp_op_o = DMI_RESP_ERR;
        end
      endcase
    end else if (dmi_req_valid_i && (dmi_req_op_i != DMI_OP_NOP) && (dmi_req_op_i != DMI_OP_WRITE)) begin
      dmi_resp_op_o = DMI_RESP_ERR;
    end
  end

  assign hart_halt_req_o = haltreq_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dmactive_q <= 1'b0;
      haltreq_q <= 1'b0;
      resumeack_q <= 1'b0;
      havereset_q <= 1'b1;
      data0_q <= 32'h0000_0000;
      data1_q <= 32'h0000_0000;
      cmderr_q <= CMDERR_NONE;
      hart_resume_req_o <= 1'b0;
    end else begin
      hart_resume_req_o <= 1'b0;

      if (dmi_req_valid_i && (dmi_req_op_i == DMI_OP_WRITE)) begin
        unique case (dmi_req_addr_i)
          REG_DATA0: begin
            data0_q <= dmi_req_wdata_i;
          end
          REG_DATA1: begin
            data1_q <= dmi_req_wdata_i;
          end
          REG_DMCONTROL: begin
            dmactive_q <= dmi_req_wdata_i[0];
            if (!dmi_req_wdata_i[0]) begin
              haltreq_q <= 1'b0;
              resumeack_q <= 1'b0;
              data0_q <= 32'h0000_0000;
              data1_q <= 32'h0000_0000;
              cmderr_q <= CMDERR_NONE;
            end else begin
              if (dmi_req_wdata_i[28]) begin
                havereset_q <= 1'b0;
              end
              if (dmi_req_wdata_i[31]) begin
                haltreq_q <= 1'b1;
                resumeack_q <= 1'b0;
              end
              if (dmi_req_wdata_i[30]) begin
                haltreq_q <= 1'b0;
                hart_resume_req_o <= 1'b1;
                resumeack_q <= 1'b1;
              end
            end
          end
          REG_ABSTRACTCS: begin
            if (dmi_req_wdata_i[10:8] != 3'd0) begin
              cmderr_q <= CMDERR_NONE;
            end
          end
          REG_COMMAND: begin
            if (cmderr_q == CMDERR_NONE) begin
              if (!command_supported) begin
                cmderr_q <= CMDERR_NOTSUP;
              end else if (!command_hart_ready) begin
                cmderr_q <= CMDERR_HALTRESUME;
              end else if (command_reg_error) begin
                cmderr_q <= CMDERR_EXCEPTION;
              end else if (!command_write_reg) begin
                data0_q <= debug_reg_rdata_i[31:0];
                data1_q <= debug_reg_rdata_i[63:32];
              end
            end
          end
          default: begin
          end
        endcase
      end

      if (hart_halted_i) begin
        haltreq_q <= 1'b0;
      end
    end
  end
endmodule
