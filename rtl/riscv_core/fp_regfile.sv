// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Architectural RV64F/D register file. f0 is a normal writable register.
module fp_regfile (
  // Clock
  input  logic        clk,

  // Three FPR read ports
  input  logic [4:0]  raddr_a_i,
  output logic [63:0] rdata_a_o,
  input  logic [4:0]  raddr_b_i,
  output logic [63:0] rdata_b_o,
  input  logic [4:0]  raddr_c_i,
  output logic [63:0] rdata_c_o,

  // WB FPR write port
  input  logic        we_i,
  input  logic [4:0]  waddr_i,
  input  logic [63:0] wdata_i,

  // Debug abstract FPR access
  input  logic [4:0]  dbg_raddr_i,
  output logic [63:0] dbg_rdata_o,
  input  logic        dbg_we_i,
  input  logic [4:0]  dbg_waddr_i,
  input  logic [63:0] dbg_wdata_i
);

  logic [63:0] regs [0:31];
  logic [31:0] raddr_a_onehot;
  logic [31:0] raddr_b_onehot;
  logic [31:0] raddr_c_onehot;
  logic [31:0] dbg_raddr_onehot;

  // Keep address decoding local to each read port.  Indexing a packed array
  // directly lets a generic mapper replicate every address bit across the
  // 32-bit data mux tree; this one-hot form gives the mapper a shared decode
  // term per selected register instead.
  assign raddr_a_onehot   = 32'b1 << raddr_a_i;
  assign raddr_b_onehot   = 32'b1 << raddr_b_i;
  assign raddr_c_onehot   = 32'b1 << raddr_c_i;
  assign dbg_raddr_onehot = 32'b1 << dbg_raddr_i;

  always_comb begin
    rdata_a_o   = '0;
    rdata_b_o   = '0;
    rdata_c_o   = '0;
    dbg_rdata_o = '0;
    for (int unsigned reg_index = 0; reg_index < 32; reg_index++) begin
      rdata_a_o   |= regs[reg_index] & {64{raddr_a_onehot[reg_index]}};
      rdata_b_o   |= regs[reg_index] & {64{raddr_b_onehot[reg_index]}};
      rdata_c_o   |= regs[reg_index] & {64{raddr_c_onehot[reg_index]}};
      dbg_rdata_o |= regs[reg_index] & {64{dbg_raddr_onehot[reg_index]}};
    end
  end

  always_ff @(posedge clk) begin
    if (we_i) begin
      regs[waddr_i] <= wdata_i;
    end
    if (dbg_we_i) begin
      regs[dbg_waddr_i] <= dbg_wdata_i;
    end
  end

endmodule
