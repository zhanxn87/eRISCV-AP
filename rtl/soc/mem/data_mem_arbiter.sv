// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Arbitration and response ownership for the single-port local data SRAM.
// Debug SBA has priority over the CPU DBus when both target DMEM.
module data_mem_arbiter (
  // Clock and reset
  input  logic        clk,
  input  logic        rst_n,

  // Debug SBA transaction (highest-priority requester)
  input  logic        sba_req_i,
  input  logic        sba_dmem_req_i,
  input  logic        sba_we_i,
  input  logic [3:0]  sba_be_i,
  input  logic [31:0] sba_addr_i,
  input  logic [31:0] sba_wdata_i,
  output logic        sba_resp_valid_o,
  output logic [31:0] sba_rdata_o,
  output logic        sba_err_o,

  // Normal CPU D-bus transaction
  input  logic        mem_req_i,
  input  logic        mem_we_i,
  input  logic [3:0]  mem_be_i,
  input  logic [31:0] mem_addr_i,
  input  logic [31:0] mem_wdata_i,
  output logic        mem_write_accept_o,
  output logic        mem_resp_valid_o,
  output logic [31:0] mem_rdata_o,
  output logic        mem_err_o,

  // Optional CPU EX-stage local-memory read transaction (lowest priority)
  input  logic        lmem_req_i,
  input  logic [31:0] lmem_addr_i,
  output logic        lmem_accept_o,
  output logic        lmem_resp_valid_o,
  output logic [31:0] lmem_rdata_o,
  output logic        lmem_err_o,

  // Single-port DTCM SRAM interface
  output logic        dmem_req_o,
  output logic        dmem_we_o,
  output logic [3:0]  dmem_be_o,
  output logic [31:0] dmem_addr_o,
  output logic [31:0] dmem_wdata_o,
  input  logic        dmem_resp_valid_i,
  input  logic        dmem_resp_write_i,
  input  logic [31:0] dmem_rdata_i,
  input  logic        dmem_err_i
);

  // Registered owner tags each synchronous DTCM response.
  typedef enum logic [1:0] {
    DMEM_OWNER_NONE,
    DMEM_OWNER_SBA,
    DMEM_OWNER_CPU,
    DMEM_OWNER_LMEM
  } dmem_owner_e;
  dmem_owner_e dmem_owner_q;

  // DTCM request arbitration: Debug SBA > normal CPU DBus > EX local load.
  always_comb begin
    dmem_req_o = 1'b0;
    dmem_we_o = 1'b0;
    dmem_be_o = '0;
    dmem_addr_o = '0;
    dmem_wdata_o = '0;
    if (sba_dmem_req_i) begin
      dmem_req_o = sba_req_i;
      dmem_we_o = sba_we_i;
      dmem_be_o = sba_be_i;
      dmem_addr_o = sba_addr_i;
      dmem_wdata_o = sba_wdata_i;
    end else if (mem_req_i) begin
      dmem_req_o = mem_req_i;
      dmem_we_o = mem_we_i;
      dmem_be_o = mem_be_i;
      dmem_addr_o = mem_addr_i;
      dmem_wdata_o = mem_wdata_i;
    end else if (lmem_req_i) begin
      dmem_req_o = 1'b1;
      dmem_addr_o = lmem_addr_i;
    end
  end

  // An EX-stage local-memory read may claim the idle local SRAM port. Normal MEM requests
  // and Debug SBA remain higher priority, so the core can fall back to D-bus
  // without knowing the SoC address map or arbitration policy.
  assign lmem_accept_o = lmem_req_i && !sba_dmem_req_i && !mem_req_i;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dmem_owner_q <= DMEM_OWNER_NONE;
    end else if (sba_dmem_req_i) begin
      dmem_owner_q <= DMEM_OWNER_SBA;
    end else if (mem_req_i) begin
      dmem_owner_q <= DMEM_OWNER_CPU;
    end else if (lmem_accept_o) begin
      dmem_owner_q <= DMEM_OWNER_LMEM;
    end else if (dmem_resp_valid_i) begin
      dmem_owner_q <= DMEM_OWNER_NONE;
    end
  end

  // Route the synchronous DTCM completion to its registered owner. CPU DTCM
  // writes are acknowledged by the interconnect in their request
  // cycle.  Consume their delayed SRAM response here so it cannot match a
  // following CPU load.  SBA writes retain their normal response.
  assign mem_resp_valid_o = dmem_resp_valid_i && (dmem_owner_q == DMEM_OWNER_CPU) &&
                            !dmem_resp_write_i;
  assign mem_rdata_o = dmem_rdata_i;
  assign mem_err_o = dmem_err_i && (dmem_owner_q == DMEM_OWNER_CPU);
  assign mem_write_accept_o = mem_req_i && mem_we_i && !sba_dmem_req_i;
  assign lmem_resp_valid_o = dmem_resp_valid_i && (dmem_owner_q == DMEM_OWNER_LMEM) &&
                              !dmem_resp_write_i;
  assign lmem_rdata_o = dmem_rdata_i;
  assign lmem_err_o = dmem_err_i && (dmem_owner_q == DMEM_OWNER_LMEM);
  assign sba_resp_valid_o = ((dmem_owner_q == DMEM_OWNER_SBA) && dmem_resp_valid_i) ||
                            (sba_req_i && !sba_dmem_req_i);
  assign sba_rdata_o = (dmem_owner_q == DMEM_OWNER_SBA) ? dmem_rdata_i : 32'h0000_0000;
  assign sba_err_o = ((dmem_owner_q == DMEM_OWNER_SBA) && dmem_err_i) ||
                     (sba_req_i && !sba_dmem_req_i);

endmodule
