// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Small architectural return-address stack for ID-stage JALR return prediction.
//
// State is updated only from resolved EX instructions at a clock edge.  The ID
// query is therefore acyclic: it observes registered state from older control
// transfers and cannot feed its own update path combinationally.
module return_address_stack #(
  parameter int DEPTH_P = 2,
  parameter int unsigned ADDR_WIDTH_P = riscv_pkg::ADDR_WIDTH
) (
  // Clock and reset
  input  logic        clk,
  input  logic        rst_n,

  // Resolved EX maintenance
  input  logic        push_valid_i,
  input  logic [ADDR_WIDTH_P-1:0] push_addr_i,
  input  logic        pop_valid_i,

  // ID-stage query
  output logic        valid_o,
  output logic [ADDR_WIDTH_P-1:0] top_addr_o
);

  localparam int COUNT_WIDTH = $clog2(DEPTH_P + 1);
  localparam int ADDR_WIDTH = (DEPTH_P > 1) ? $clog2(DEPTH_P) : 1;
  localparam logic [COUNT_WIDTH-1:0] DEPTH_COUNT = COUNT_WIDTH'(DEPTH_P);

  logic [ADDR_WIDTH_P-1:0] stack_q [0:DEPTH_P-1];
  logic [COUNT_WIDTH-1:0] depth_q;
  logic [ADDR_WIDTH-1:0] stack_index;

  assign valid_o = (depth_q != '0);
  assign stack_index = depth_q[ADDR_WIDTH-1:0];
  assign top_addr_o = valid_o ? stack_q[stack_index - 1'b1] : '0;

  // Stack contents do not need reset because depth_q gates every read.  A push
  // while full is ignored; a pop while empty is ignored.  EX emits at most one
  // maintenance operation per completed instruction.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      depth_q <= '0;
    end else if (push_valid_i) begin
      if (depth_q < DEPTH_COUNT) begin
        stack_q[stack_index] <= push_addr_i;
        depth_q <= depth_q + 1'b1;
      end
    end else if (pop_valid_i) begin
      if (depth_q != '0)
        depth_q <= depth_q - 1'b1;
    end
  end

endmodule
