// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// AP boot ROM: the only instruction source before I-Cache and DDR boot are
// implemented. The ROM remains read-only to the hart and may be initialized
// by a board-specific memory-init file.
module ap_boot_rom
  import ap_soc_pkg::*;
#(
  parameter int unsigned SIZE_BYTES_P = 64 * 1024,
  parameter string INIT_FILE_P = ""
) (
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  req_i,
  input  logic [AP_PADDR_W-1:0] addr_i,
  output logic                  ready_o,
  output logic                  rvalid_o,
  output logic [31:0]           rdata_o
);

  localparam int unsigned WORDS_P = SIZE_BYTES_P / 4;
  localparam int unsigned ADDR_W_P = $clog2(WORDS_P);

  logic [31:0] mem [0:WORDS_P-1];
  logic boot_rom_addr;

  initial begin
    if (INIT_FILE_P != "")
      $readmemh(INIT_FILE_P, mem);
  end

  assign boot_rom_addr = ap_addr_in_range(addr_i, AP_BOOT_ROM_BASE,
                                          AP_BOOT_ROM_BASE + SIZE_BYTES_P);
  assign ready_o = 1'b1;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rvalid_o <= 1'b0;
      rdata_o <= 32'h0000_0013; // NOP while reset is active.
    end else begin
      rvalid_o <= req_i;
      if (req_i)
        rdata_o <= boot_rom_addr ? mem[addr_i[2 +: ADDR_W_P]] : 32'h0000_0013;
    end
  end

endmodule
