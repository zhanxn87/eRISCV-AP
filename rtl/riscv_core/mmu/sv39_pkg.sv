// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Sv39 constants and types shared by the per-hart ITLB, DTLB, and PTW.
package sv39_pkg;
  import riscv_pkg::*;

  localparam int unsigned SV39_LEVELS = 3;
  localparam int unsigned SV39_VPN_W = 27;
  localparam int unsigned SV39_PPN_W = 44;
  localparam int unsigned SV39_ASID_W = 16;
  localparam int unsigned SV39_PAGE_SHIFT = 12;
  localparam int unsigned SV39_PTE_BYTES = 8;
  localparam logic [3:0] SV39_MODE_BARE = 4'd0;
  localparam logic [3:0] SV39_MODE_SV39 = 4'd8;

  typedef enum logic [1:0] {
    SV39_ACCESS_FETCH = 2'd0,
    SV39_ACCESS_LOAD  = 2'd1,
    SV39_ACCESS_STORE = 2'd2
  } sv39_access_e;

  typedef struct packed {
    logic [3:0]  mode;
    logic [15:0] asid;
    logic [43:0] ppn;
  } satp_sv39_t;

  function automatic satp_sv39_t decode_satp(input xlen_t satp);
    satp_sv39_t decoded;
    begin
      decoded.mode = satp[63:60];
      decoded.asid = satp[59:44];
      decoded.ppn = satp[43:0];
      return decoded;
    end
  endfunction
endpackage
