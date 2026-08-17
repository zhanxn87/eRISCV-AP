// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

import riscv_pkg::*;

// Two-source bypass network for EX-stage operand forwarding.
// MEM/WB has lower priority than EX/MEM so the newest producer wins.
module forwarding_unit #(
  parameter int unsigned XLEN_P = riscv_pkg::CORE_XLEN
) (
  input  logic [4:0]  rs1_addr_i,
  input  logic [XLEN_P-1:0] rs1_data_i,
  input  logic [4:0]  rs2_addr_i,
  input  logic [XLEN_P-1:0] rs2_data_i,

  input  var ex_mem_t ex_mem_i,
  input  var mem_wb_t mem_wb_i,

  output logic [XLEN_P-1:0] rs1_data_o,
  output logic [XLEN_P-1:0] rs2_data_o
);

  // EX/MEM is the youngest completed producer. A load there has no available
  // result yet and is instead covered by the top-level load-use interlock.
  logic ex_mem_rs1_match;
  logic ex_mem_rs2_match;

  // MEM/WB is an older producer and therefore loses to a matching EX/MEM
  // result in the operand mux below.
  logic mem_wb_rs1_match;
  logic mem_wb_rs2_match;

  assign ex_mem_rs1_match = ex_mem_i.valid && ex_mem_i.rd_we && !ex_mem_i.mem_load &&
                            (ex_mem_i.rd_addr != 5'd0) &&
                            (ex_mem_i.rd_addr == rs1_addr_i);
  assign ex_mem_rs2_match = ex_mem_i.valid && ex_mem_i.rd_we && !ex_mem_i.mem_load &&
                            (ex_mem_i.rd_addr != 5'd0) &&
                            (ex_mem_i.rd_addr == rs2_addr_i);
  assign mem_wb_rs1_match = mem_wb_i.valid && mem_wb_i.rd_we &&
                            (mem_wb_i.rd_addr != 5'd0) &&
                            (mem_wb_i.rd_addr == rs1_addr_i);
  assign mem_wb_rs2_match = mem_wb_i.valid && mem_wb_i.rd_we &&
                            (mem_wb_i.rd_addr != 5'd0) &&
                            (mem_wb_i.rd_addr == rs2_addr_i);

  // Apply the older MEM/WB value first, then override it with EX/MEM so the
  // source-order mirrors the required forwarding priority.
  always_comb begin
    rs1_data_o = rs1_data_i;
    rs2_data_o = rs2_data_i;

    if (mem_wb_rs1_match) begin
      rs1_data_o = mem_wb_i.wb_data;
    end
    if (mem_wb_rs2_match) begin
      rs2_data_o = mem_wb_i.wb_data;
    end

    if (ex_mem_rs1_match) begin
      rs1_data_o = ex_mem_i.ex_result;
    end
    if (ex_mem_rs2_match) begin
      rs2_data_o = ex_mem_i.ex_result;
    end
  end

endmodule
