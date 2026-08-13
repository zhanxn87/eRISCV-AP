// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Async assertion, synchronous release reset synchronizer for one clock domain.
module reset_sync (
  input  logic clk_i,
  input  logic arst_n_i,
  output logic srst_n_o
);

  (* ASYNC_REG = "TRUE" *) logic [1:0] release_q;

  always_ff @(posedge clk_i or negedge arst_n_i) begin
    if (!arst_n_i)
      release_q <= 2'b00;
    else
      release_q <= {release_q[0], 1'b1};
  end

  assign srst_n_o = release_q[1];

endmodule
