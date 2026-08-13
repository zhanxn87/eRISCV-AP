// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// RISC-V CLINT (Core-Local Interruptor) — MSIP, MTIMECMP, MTIME.
// Standard RISC-V address map, D-bus attached (not APB).
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

  // D-bus interface
  input  logic        req_i,
  input  logic        we_i,
  input  logic [3:0]  be_i,
  input  logic [31:0] addr_i,
  input  logic [31:0] wdata_i,
  output logic        hit_o,
  output logic        write_accept_o,
  output logic        resp_valid_o,
  output logic [31:0] rdata_o,
  output logic        err_o,

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

  assign msip_hit        = (addr_i == MSIP_ADDR);
  assign mtimecmp_lo_hit = (addr_i == MTIMECMP_LO_ADDR);
  assign mtimecmp_hi_hit = (addr_i == MTIMECMP_HI_ADDR);
  assign mtime_lo_hit    = (addr_i == MTIME_LO_ADDR);
  assign mtime_hi_hit    = (addr_i == MTIME_HI_ADDR);
  assign hit_o = msip_hit | mtimecmp_lo_hit | mtimecmp_hi_hit | mtime_lo_hit | mtime_hi_hit;
  assign write_accept_o = req_i && we_i && hit_o;
  assign err_o = 1'b0;

  // =========================================================================
  // Read data mux
  // =========================================================================
  always_comb begin
    unique case (1'b1)
      msip_hit:        rdata_o = {31'h0, msip_q};
      mtimecmp_lo_hit: rdata_o = mtimecmp_q[31:0];
      mtimecmp_hi_hit: rdata_o = mtimecmp_q[63:32];
      mtime_lo_hit:    rdata_o = mtime_q[31:0];
      mtime_hi_hit:    rdata_o = mtime_q[63:32];
      default:         rdata_o = 32'h0;
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
      resp_valid_o <= 1'b0;
    end else begin
      // MTIME free-running counter
      mtime_q <= mtime_q + 64'd1;

      // Write handling
      if (req_i && hit_o && we_i) begin
        if (msip_hit)
          msip_q <= apply_byte_enables({31'h0, msip_q}, wdata_i, be_i) != 32'h0;
        if (mtimecmp_lo_hit)
          mtimecmp_q[31:0]  <= apply_byte_enables(mtimecmp_q[31:0],  wdata_i, be_i);
        if (mtimecmp_hi_hit)
          mtimecmp_q[63:32] <= apply_byte_enables(mtimecmp_q[63:32], wdata_i, be_i);
        // MTIME writes are allowed (for testability)
        if (mtime_lo_hit)
          mtime_q[31:0]  <= apply_byte_enables(mtime_q[31:0],  wdata_i, be_i);
        if (mtime_hi_hit)
          mtime_q[63:32] <= apply_byte_enables(mtime_q[63:32], wdata_i, be_i);
      end

      // Reads return after one cycle. A valid write commits on this edge and
      // is acknowledged by the interconnect in the request cycle.
      resp_valid_o <= req_i && hit_o && !we_i;
    end
  end

  // =========================================================================
  // IRQ generation
  // =========================================================================
  assign msip_o  = msip_q;
  assign mtip_o  = (mtime_q >= mtimecmp_q);
  assign mtime_o = mtime_q;

endmodule
