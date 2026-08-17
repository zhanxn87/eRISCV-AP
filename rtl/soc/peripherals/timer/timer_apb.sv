// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

module timer_apb (
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
  output logic        irq_o,
  output logic        busy_o
);

  localparam logic [7:0] REG_CTRL    = 8'h00;
  localparam logic [7:0] REG_COUNT   = 8'h04;
  localparam logic [7:0] REG_COMPARE = 8'h08;
  localparam logic [7:0] REG_STATUS  = 8'h0c;

  logic        apb_access;
  logic [7:0]  reg_offset;
  logic [31:0] ctrl_q;
  logic [31:0] count_q;
  logic [31:0] compare_q;
  logic        expired_q;

  assign apb_access = psel_i & penable_i;
  assign reg_offset = paddr_i[7:0];
  assign pready_o   = 1'b1;
  assign pslverr_o  = apb_access &&
                      (reg_offset != REG_CTRL) &&
                      (reg_offset != REG_COUNT) &&
                      (reg_offset != REG_COMPARE) &&
                      (reg_offset != REG_STATUS);
  assign irq_o      = expired_q & ctrl_q[1];
  assign busy_o     = ctrl_q[0];

  always_comb begin
    unique case (reg_offset)
      REG_CTRL:    prdata_o = ctrl_q;
      REG_COUNT:   prdata_o = count_q;
      REG_COMPARE: prdata_o = compare_q;
      REG_STATUS:  prdata_o = {31'h00000000, expired_q};
      default:     prdata_o = 32'h0000_0000;
    endcase
  end

  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      ctrl_q    <= 32'h0000_0000;
      count_q   <= 32'h0000_0000;
      compare_q <= 32'h0000_0000;
      expired_q <= 1'b0;
    end else begin
      if (ctrl_q[0]) begin
        count_q <= count_q + 32'h0000_0001;
        if ((compare_q != 32'h0000_0000) && (count_q >= compare_q)) begin
          expired_q <= 1'b1;
        end
      end

      if (apb_access && pwrite_i && !pslverr_o) begin
        unique case (reg_offset)
          REG_CTRL: begin
            ctrl_q <= pwdata_i;
          end
          REG_COUNT: begin
            count_q <= pwdata_i;
          end
          REG_COMPARE: begin
            compare_q <= pwdata_i;
          end
          REG_STATUS: begin
            if (pstrb_i[0] && pwdata_i[0]) begin
              expired_q <= 1'b0;
            end
          end
          default: begin
          end
        endcase
      end
    end
  end

endmodule
