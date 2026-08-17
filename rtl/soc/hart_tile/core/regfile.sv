// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// XLEN-wide GPR file with x0 hardwired to zero and write-through reads.
module regfile #(
  parameter int unsigned XLEN_P = riscv_pkg::CORE_XLEN
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic [4:0]  raddr_a_i,
  output logic [XLEN_P-1:0] rdata_a_o,
  input  logic [4:0]  raddr_b_i,
  output logic [XLEN_P-1:0] rdata_b_o,
  input  logic [4:0]  waddr_a_i,
  input  logic [XLEN_P-1:0] wdata_a_i,
  input  logic        we_a_i,
  input  logic [4:0]  dbg_raddr_i,
  output logic [XLEN_P-1:0] dbg_rdata_o,
  input  logic [4:0]  dbg_waddr_i,
  input  logic [XLEN_P-1:0] dbg_wdata_i,
  input  logic        dbg_we_i
);

  logic [XLEN_P-1:0] regs_q [0:31];
  integer index;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (index = 0; index < 32; index = index + 1) begin
        regs_q[index] <= '0;
      end
    end else begin
      if (we_a_i && (waddr_a_i != 5'd0)) begin
        regs_q[waddr_a_i] <= wdata_a_i;
      end
      if (dbg_we_i && (dbg_waddr_i != 5'd0)) begin
        regs_q[dbg_waddr_i] <= dbg_wdata_i;
      end
    end
  end

  assign rdata_a_o = (raddr_a_i == 5'd0) ? '0 :
                     ((we_a_i && (waddr_a_i == raddr_a_i)) ? wdata_a_i : regs_q[raddr_a_i]);
  assign rdata_b_o = (raddr_b_i == 5'd0) ? '0 :
                     ((we_a_i && (waddr_a_i == raddr_b_i)) ? wdata_a_i : regs_q[raddr_b_i]);
  assign dbg_rdata_o = (dbg_raddr_i == 5'd0) ? '0 :
                       ((dbg_we_i && (dbg_waddr_i == dbg_raddr_i)) ? dbg_wdata_i : regs_q[dbg_raddr_i]);

endmodule
