// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

import soc_pkg::*;

// Data bus interconnect: combinatorial request decoder with a registered target
// tag for delayed responses. Address ranges are defined in soc_pkg.
module dbus_interconnect (
  // Clock and reset
  input  logic        clk,
  input  logic        rst_n,

  // Data bus interface from core
  input  logic        dbus_req_i,
  input  logic [31:0] dbus_addr_i,
  input  logic [31:0] dbus_wdata_i,
  input  logic        dbus_we_i,
  input  logic [3:0]  dbus_be_i,
  output logic        dbus_resp_valid_o,
  output logic [31:0] dbus_rdata_o,
  output logic        dbus_err_o,

  // Instruction memory interface
  output logic        imem_req_o,
  output logic        imem_we_o,
  output logic [3:0]  imem_be_o,
  output logic [31:0] imem_addr_o,
  output logic [31:0] imem_wdata_o,
  input  logic        imem_resp_valid_i,
  input  logic [31:0] imem_rdata_i,
  input  logic        imem_err_i,

  // Data memory interface
  output logic        mem_req_o,
  output logic        mem_we_o,
  output logic [3:0]  mem_be_o,
  output logic [31:0] mem_addr_o,
  output logic [31:0] mem_wdata_o,
  input  logic        mem_resp_valid_i,
  input  logic [31:0] mem_rdata_i,
  input  logic        mem_err_i,
  input  logic        mem_write_accept_i,

  // System SRAM interface
  output logic        system_sram_req_o,
  output logic        system_sram_we_o,
  output logic [3:0]  system_sram_be_o,
  output logic [31:0] system_sram_addr_o,
  output logic [31:0] system_sram_wdata_o,
  input  logic        system_sram_resp_valid_i,
  input  logic [31:0] system_sram_rdata_i,
  input  logic        system_sram_err_i,

  // DMA control interface
  output logic        dma_req_o,
  output logic        dma_we_o,
  output logic [31:0] dma_addr_o,
  output logic [31:0] dma_wdata_o,
  input  logic        dma_resp_valid_i,
  input  logic [31:0] dma_rdata_i,
  input  logic        dma_err_i,

  // APB bridge interface
  output logic        apb_req_o,
  output logic        apb_we_o,
  output logic [3:0]  apb_be_o,
  output logic [31:0] apb_addr_o,
  output logic [31:0] apb_wdata_o,
  input  logic        apb_resp_valid_i,
  input  logic [31:0] apb_rdata_i,
  input  logic        apb_err_i,

  // PLIC interface
  output logic        plic_req_o,
  output logic        plic_we_o,
  output logic [3:0]  plic_be_o,
  output logic [31:0] plic_addr_o,
  output logic [31:0] plic_wdata_o,
  input  logic        plic_resp_valid_i,
  input  logic [31:0] plic_rdata_i,
  input  logic        plic_err_i,
  input  logic        plic_write_accept_i,

  // CLINT interface
  output logic        clint_req_o,
  output logic        clint_we_o,
  output logic [3:0]  clint_be_o,
  output logic [31:0] clint_addr_o,
  output logic [31:0] clint_wdata_o,
  input  logic        clint_resp_valid_i,
  input  logic [31:0] clint_rdata_i,
  input  logic        clint_err_i,
  input  logic        clint_write_accept_i
);

  typedef enum logic [2:0] {
    DBUS_TARGET_IMEM,
    DBUS_TARGET_DMEM,
    DBUS_TARGET_SYSTEM_SRAM,
    DBUS_TARGET_DMA,
    DBUS_TARGET_APB,
    DBUS_TARGET_PLIC,
    DBUS_TARGET_CLINT
  } dbus_target_e;

  // Address decoding and delayed-response ownership
  logic apb_sel, plic_sel, clint_sel, imem_sel, dmem_sel, system_sram_sel, dma_sel, unmapped_sel;
  logic fast_store_response;
  dbus_target_e request_target;
  dbus_target_e response_target_q;

  assign apb_sel      = dbus_req_i & is_apb_addr(dbus_addr_i);
  assign plic_sel     = dbus_req_i & is_plic_addr(dbus_addr_i);
  assign clint_sel    = dbus_req_i & is_clint_addr(dbus_addr_i);
  assign imem_sel     = dbus_req_i & is_imem_addr(dbus_addr_i);
  assign dmem_sel     = dbus_req_i & is_dmem_addr(dbus_addr_i);
  assign system_sram_sel = dbus_req_i & is_system_sram_addr(dbus_addr_i);
  assign dma_sel      = dbus_req_i & is_dma_addr(dbus_addr_i);
  assign unmapped_sel = dbus_req_i & !apb_sel & !plic_sel & !clint_sel & !imem_sel & !dmem_sel &
                        !system_sram_sel & !dma_sel;

  always_comb begin
    request_target = DBUS_TARGET_IMEM;
    if (dmem_sel)
      request_target = DBUS_TARGET_DMEM;
    else if (system_sram_sel)
      request_target = DBUS_TARGET_SYSTEM_SRAM;
    else if (dma_sel)
      request_target = DBUS_TARGET_DMA;
    else if (apb_sel)
      request_target = DBUS_TARGET_APB;
    else if (plic_sel)
      request_target = DBUS_TARGET_PLIC;
    else if (clint_sel)
      request_target = DBUS_TARGET_CLINT;
  end

  // Request routing: forward requests to the selected target.
  assign imem_req_o   = imem_sel;
  assign imem_we_o    = dbus_we_i;
  assign imem_be_o    = dbus_be_i;
  assign imem_addr_o  = dbus_addr_i;
  assign imem_wdata_o = dbus_wdata_i;

  assign mem_req_o   = dmem_sel;
  assign mem_we_o    = dbus_we_i;
  assign mem_be_o    = dbus_be_i;
  assign mem_addr_o  = dbus_addr_i;
  assign mem_wdata_o = dbus_wdata_i;

  assign system_sram_req_o   = system_sram_sel;
  assign system_sram_we_o    = dbus_we_i;
  assign system_sram_be_o    = dbus_be_i;
  assign system_sram_addr_o  = dbus_addr_i;
  assign system_sram_wdata_o = dbus_wdata_i;

  assign dma_req_o   = dma_sel;
  assign dma_we_o    = dbus_we_i;
  assign dma_addr_o  = dbus_addr_i;
  assign dma_wdata_o = dbus_wdata_i;

  assign apb_req_o   = apb_sel;
  assign apb_we_o    = dbus_we_i;
  assign apb_be_o    = dbus_be_i;
  assign apb_addr_o  = dbus_addr_i;
  assign apb_wdata_o = dbus_wdata_i;

  assign plic_req_o   = plic_sel;
  assign plic_we_o    = dbus_we_i;
  assign plic_be_o    = dbus_be_i;
  assign plic_addr_o  = dbus_addr_i;
  assign plic_wdata_o = dbus_wdata_i;

  assign clint_req_o   = clint_sel;
  assign clint_we_o    = dbus_we_i;
  assign clint_be_o    = dbus_be_i;
  assign clint_addr_o  = dbus_addr_i;
  assign clint_wdata_o = dbus_wdata_i;

  // Targets that commit a valid write on this edge return a normal D-bus
  // response immediately. The core stays independent of this address map;
  // it observes only the standard request/response handshake.
  assign fast_store_response = mem_write_accept_i || plic_write_accept_i ||
                               clint_write_accept_i;

  // All non-immediate accesses use the registered request target. This keeps
  // response-valid arbitration out of the return-data path and lets synthesis
  // build a balanced target mux. Fast local stores and unmapped accesses retain
  // their existing same-cycle completion.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      response_target_q <= DBUS_TARGET_IMEM;
    else if (dbus_req_i && !fast_store_response && !unmapped_sel)
      response_target_q <= request_target;
  end

  always_comb begin
    dbus_resp_valid_o = fast_store_response | unmapped_sel;
    dbus_rdata_o = 32'h0000_0000;
    dbus_err_o = unmapped_sel;

    if (!fast_store_response && !unmapped_sel) begin
      unique case (response_target_q)
        DBUS_TARGET_IMEM: begin
          dbus_resp_valid_o = imem_resp_valid_i;
          dbus_rdata_o = imem_rdata_i;
          dbus_err_o = imem_resp_valid_i && imem_err_i;
        end
        DBUS_TARGET_DMEM: begin
          dbus_resp_valid_o = mem_resp_valid_i;
          dbus_rdata_o = mem_rdata_i;
          dbus_err_o = mem_resp_valid_i && mem_err_i;
        end
        DBUS_TARGET_SYSTEM_SRAM: begin
          dbus_resp_valid_o = system_sram_resp_valid_i;
          dbus_rdata_o = system_sram_rdata_i;
          dbus_err_o = system_sram_resp_valid_i && system_sram_err_i;
        end
        DBUS_TARGET_DMA: begin
          dbus_resp_valid_o = dma_resp_valid_i;
          dbus_rdata_o = dma_rdata_i;
          dbus_err_o = dma_resp_valid_i && dma_err_i;
        end
        DBUS_TARGET_APB: begin
          dbus_resp_valid_o = apb_resp_valid_i;
          dbus_rdata_o = apb_rdata_i;
          dbus_err_o = apb_resp_valid_i && apb_err_i;
        end
        DBUS_TARGET_PLIC: begin
          dbus_resp_valid_o = plic_resp_valid_i;
          dbus_rdata_o = plic_rdata_i;
          dbus_err_o = plic_resp_valid_i && plic_err_i;
        end
        DBUS_TARGET_CLINT: begin
          dbus_resp_valid_o = clint_resp_valid_i;
          dbus_rdata_o = clint_rdata_i;
          dbus_err_o = clint_resp_valid_i && clint_err_i;
        end
        default: ;
      endcase
    end
  end

endmodule
