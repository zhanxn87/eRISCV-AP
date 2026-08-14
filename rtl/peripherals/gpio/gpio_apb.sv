// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

module gpio_apb (
  input  logic        pclk,
  input  logic        presetn,
  input  logic        psel_i,
  input  logic        penable_i,
  input  logic        pwrite_i,
  input  logic [31:0] paddr_i,
  input  logic [31:0] pwdata_i,
  input  logic [3:0]  pstrb_i,
  output logic        pready_o,
  output logic [31:0] prdata_o,
  output logic        pslverr_o,

  input  logic [31:0] gpio_i,
  output logic [31:0] gpio_o,
  output logic [31:0] gpio_oe_o
);

  localparam logic [7:0] REG_OUT = 8'h00;
  localparam logic [7:0] REG_IN  = 8'h04;
  localparam logic [7:0] REG_DIR = 8'h08;

  logic        apb_access;
  logic [7:0]  reg_offset;
  logic [31:0] out_q;
  logic [31:0] dir_q;

  assign apb_access = psel_i & penable_i;
  assign reg_offset = paddr_i[7:0];
  assign pready_o   = 1'b1;
  assign pslverr_o  = apb_access &&
                      (reg_offset != REG_OUT) &&
                      (reg_offset != REG_IN) &&
                      (reg_offset != REG_DIR);

  assign gpio_o    = out_q;
  assign gpio_oe_o = dir_q;

  always_comb begin
    unique case (reg_offset)
      REG_OUT: prdata_o = out_q;
      REG_IN:  prdata_o = gpio_i;
      REG_DIR: prdata_o = dir_q;
      default: prdata_o = 32'h0000_0000;
    endcase
  end

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      out_q <= 32'h0000_0000;
      dir_q <= 32'h0000_0000;
    end else if (apb_access && pwrite_i && !pslverr_o) begin
      unique case (reg_offset)
        REG_OUT: begin
          if (pstrb_i[0]) out_q[7:0]   <= pwdata_i[7:0];
          if (pstrb_i[1]) out_q[15:8]  <= pwdata_i[15:8];
          if (pstrb_i[2]) out_q[23:16] <= pwdata_i[23:16];
          if (pstrb_i[3]) out_q[31:24] <= pwdata_i[31:24];
        end
        REG_DIR: begin
          if (pstrb_i[0]) dir_q[7:0]   <= pwdata_i[7:0];
          if (pstrb_i[1]) dir_q[15:8]  <= pwdata_i[15:8];
          if (pstrb_i[2]) dir_q[23:16] <= pwdata_i[23:16];
          if (pstrb_i[3]) dir_q[31:24] <= pwdata_i[31:24];
        end
        default: begin
        end
      endcase
    end
  end

endmodule
