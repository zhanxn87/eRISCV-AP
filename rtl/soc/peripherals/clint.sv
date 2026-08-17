// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// RISC-V CLINT (Core-Local Interruptor) — MSIP, MTIMECMP, MTIME.
// Standard RISC-V address map, APB-attached.
//
// Address map (relative to CLINT_BASE):
//   0x0000_0000: MSIP      (1 bit, bit 0 = software interrupt pending)
//   0x0000_4000: MTIMECMP  (64-bit, low word)
//   0x0000_4004: MTIMECMP  (64-bit, high word)
//   0x0000_BFF8: MTIME     (64-bit, low word, read-only counter)
//   0x0000_BFFC: MTIME     (64-bit, high word, read-only counter)
//
// IRQ outputs:  msip (mip bit 3), mtip (mip bit 7)
module clint #(
  parameter logic [31:0] BASE_ADDR = 32'h0200_0000
) (
  input  logic        clk,
  input  logic        rst_n,

  // APB slave interface
  input  logic        psel_i,
  input  logic        penable_i,
  input  logic        pwrite_i,
  input  logic [31:0] paddr_i,
  input  logic [31:0] pwdata_i,
  input  logic [3:0]  pstrb_i,
  output logic        pready_o,
  output logic [31:0] prdata_o,
  output logic        pslverr_o,

  // IRQ outputs
  output logic        msip_o,
  output logic        mtip_o,
  output logic [63:0] mtime_o
);

  // CLINT register addresses
  localparam logic [31:0] MSIP_ADDR        = BASE_ADDR + 32'h0000_0000;
  localparam logic [31:0] MTIMECMP_LO_ADDR = BASE_ADDR + 32'h0000_4000;
  localparam logic [31:0] MTIMECMP_HI_ADDR = BASE_ADDR + 32'h0000_4004;
  localparam logic [31:0] MTIME_LO_ADDR    = BASE_ADDR + 32'h0000_BFF8;
  localparam logic [31:0] MTIME_HI_ADDR    = BASE_ADDR + 32'h0000_BFFC;

  // Architectural CLINT state
  logic        msip_q;
  logic [63:0] mtime_q;
  logic [63:0] mtimecmp_q;

  // Address-decode terms
  logic        msip_hit;
  logic        mtimecmp_lo_hit, mtimecmp_hi_hit;
  logic        mtime_lo_hit,    mtime_hi_hit;

  logic apb_access;
  logic valid_addr;

  assign apb_access = psel_i && penable_i;
  assign msip_hit        = (paddr_i == MSIP_ADDR);
  assign mtimecmp_lo_hit = (paddr_i == MTIMECMP_LO_ADDR);
  assign mtimecmp_hi_hit = (paddr_i == MTIMECMP_HI_ADDR);
  assign mtime_lo_hit    = (paddr_i == MTIME_LO_ADDR);
  assign mtime_hi_hit    = (paddr_i == MTIME_HI_ADDR);
  assign valid_addr = msip_hit | mtimecmp_lo_hit | mtimecmp_hi_hit |
                      mtime_lo_hit | mtime_hi_hit;
  assign pready_o = 1'b1;
  assign pslverr_o = apb_access && !valid_addr;

  // =========================================================================
  // Read data mux
  // =========================================================================
  always_comb begin
    unique case (1'b1)
      msip_hit:        prdata_o = {31'h0, msip_q};
      mtimecmp_lo_hit: prdata_o = mtimecmp_q[31:0];
      mtimecmp_hi_hit: prdata_o = mtimecmp_q[63:32];
      mtime_lo_hit:    prdata_o = mtime_q[31:0];
      mtime_hi_hit:    prdata_o = mtime_q[63:32];
      default:         prdata_o = 32'h0;
    endcase
  end

  // =========================================================================
  // Write logic
  // =========================================================================
  function automatic logic [31:0] apply_byte_enables(
    input logic [31:0] cur, input logic [31:0] wdata, input logic [3:0] be
  );
    logic [31:0] m;
    m = cur;
    if (be[0]) m[7:0]   = wdata[7:0];
    if (be[1]) m[15:8]  = wdata[15:8];
    if (be[2]) m[23:16] = wdata[23:16];
    if (be[3]) m[31:24] = wdata[31:24];
    return m;
  endfunction

  // =========================================================================
  // Sequential state
  // =========================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      msip_q      <= 1'b0;
      mtime_q     <= 64'h0;
      mtimecmp_q  <= 64'hFFFF_FFFF_FFFF_FFFF;
    end else begin
      // MTIME free-running counter
      mtime_q <= mtime_q + 64'd1;

      // APB write handling
      if (apb_access && valid_addr && pwrite_i) begin
        if (msip_hit)
          msip_q <= apply_byte_enables({31'h0, msip_q}, pwdata_i, pstrb_i) != 32'h0;
        if (mtimecmp_lo_hit)
          mtimecmp_q[31:0]  <= apply_byte_enables(mtimecmp_q[31:0],  pwdata_i, pstrb_i);
        if (mtimecmp_hi_hit)
          mtimecmp_q[63:32] <= apply_byte_enables(mtimecmp_q[63:32], pwdata_i, pstrb_i);
        // MTIME writes are allowed (for testability)
        if (mtime_lo_hit)
          mtime_q[31:0]  <= apply_byte_enables(mtime_q[31:0],  pwdata_i, pstrb_i);
        if (mtime_hi_hit)
          mtime_q[63:32] <= apply_byte_enables(mtime_q[63:32], pwdata_i, pstrb_i);
      end

    end
  end

  // =========================================================================
  // IRQ generation
  // =========================================================================
  assign msip_o  = msip_q;
  assign mtip_o  = (mtime_q >= mtimecmp_q);
  assign mtime_o = mtime_q;

endmodule
