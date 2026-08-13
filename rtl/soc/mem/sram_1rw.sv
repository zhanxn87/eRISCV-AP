// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Portable single-port SRAM wrapper.
//
// The behavioral array is intended to infer FPGA block RAM and is also the
// reference simulation model.  ASIC integration may replace this module with
// a memory-compiler wrapper that preserves this 1RW, byte-write, synchronous
// read-first contract.  The storage array and read-data register are not reset.
module sram_1rw #(
  parameter int ADDR_WIDTH = 13,
  parameter int DATA_WIDTH = 32,
  parameter int BYTE_LANES = DATA_WIDTH / 8
) (
  // SRAM clock
  input  logic                  clk,

  // Single read/write port
  input  logic                  en_i,
  input  logic                  we_i,
  input  logic [BYTE_LANES-1:0] be_i,
  input  logic [ADDR_WIDTH-1:0] addr_i,
  input  logic [DATA_WIDTH-1:0] wdata_i,
  output logic [DATA_WIDTH-1:0] rdata_o
);

  // Tool-specific RAM-style attributes are ignored by ASIC synthesis, while
  // common FPGA flows use them as an inference hint rather than a dependency.
  (* ram_style = "block", ramstyle = "no_rw_check" *)
  logic [DATA_WIDTH-1:0] mem [0:(1 << ADDR_WIDTH)-1];
  integer lane;

  // A simultaneous read/write returns the pre-write word (read-first).
  always_ff @(posedge clk) begin
    if (en_i) begin
      rdata_o <= mem[addr_i];
      if (we_i) begin
        for (lane = 0; lane < BYTE_LANES; lane = lane + 1) begin
          if (be_i[lane]) begin
            mem[addr_i][lane*8 +: 8] <= wdata_i[lane*8 +: 8];
          end
        end
      end
    end
  end

endmodule
