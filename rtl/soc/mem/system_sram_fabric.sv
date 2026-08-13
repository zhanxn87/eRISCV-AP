// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

import soc_pkg::*;

// Interleaved System SRAM fabric. Every bank has one physical 1RW port; CPU
// and generic DMA arbitrate independently at each bank.
module system_sram_fabric #(
  parameter int NUM_BANKS = soc_pkg::SYSTEM_SRAM_BANK_COUNT,
  parameter int BANK_ADDR_WIDTH = soc_pkg::SYSTEM_SRAM_BANK_WORD_ADDR_WIDTH,
  // Bypass the CPU load-response register. Keep disabled by default so a
  // banked BRAM read cannot feed the core redirect path in the same cycle.
  parameter bit SYS_SRAM_LOAD_BYPASS_P = 1'b0
) (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        cpu_req_valid_i,
  input  logic        cpu_req_we_i,
  input  logic [3:0]  cpu_req_be_i,
  input  logic [31:0] cpu_req_addr_i,
  input  logic [31:0] cpu_req_wdata_i,
  output logic        cpu_req_ready_o,
  output logic        cpu_resp_valid_o,
  output logic [31:0] cpu_resp_rdata_o,
  output logic        cpu_resp_err_o,

  input  logic        dma_req_valid_i,
  input  logic        dma_req_we_i,
  input  logic [3:0]  dma_req_be_i,
  input  logic [31:0] dma_req_addr_i,
  input  logic [31:0] dma_req_wdata_i,
  output logic        dma_req_ready_o,
  output logic        dma_resp_valid_o,
  output logic [31:0] dma_resp_rdata_o,
  output logic        dma_resp_err_o
);

  localparam int BANK_BITS = $clog2(NUM_BANKS);
  localparam int BANK_SEL_LSB = 2;
  localparam int BANK_ADDR_LSB = BANK_SEL_LSB + BANK_BITS;

  logic [BANK_BITS-1:0] cpu_bank_sel, dma_bank_sel;
  logic [BANK_BITS-1:0] cpu_response_bank_q, dma_response_bank_q;
  logic cpu_response_we_q;
  logic [NUM_BANKS-1:0] cpu_req_ready_by_bank, cpu_resp_valid_by_bank, cpu_resp_err_by_bank;
  logic [NUM_BANKS-1:0] dma_req_ready_by_bank, dma_resp_valid_by_bank, dma_resp_err_by_bank;
  logic [31:0] cpu_resp_rdata_by_bank [NUM_BANKS];
  logic [31:0] dma_resp_rdata_by_bank [NUM_BANKS];
  logic [NUM_BANKS-1:0] bank_req_valid, bank_req_we, bank_resp_valid, bank_resp_err;
  logic [3:0] bank_req_be [NUM_BANKS];
  logic [31:0] bank_req_addr [NUM_BANKS], bank_req_wdata [NUM_BANKS], bank_resp_rdata [NUM_BANKS];
  logic [BANK_ADDR_WIDTH-1:0] bank_word_addr [NUM_BANKS];
  logic cpu_resp_valid;
  logic [31:0] cpu_resp_rdata;
  logic cpu_resp_err;

  assign cpu_bank_sel = cpu_req_addr_i[BANK_SEL_LSB +: BANK_BITS];
  assign dma_bank_sel = dma_req_addr_i[BANK_SEL_LSB +: BANK_BITS];
  assign cpu_req_ready_o = cpu_req_valid_i && cpu_req_ready_by_bank[cpu_bank_sel];
  assign dma_req_ready_o = dma_req_valid_i && dma_req_ready_by_bank[dma_bank_sel];

  // Each upstream master permits one outstanding request. Remember the bank
  // that accepted it so the response is selected by a balanced indexed mux,
  // rather than an eight-bank valid-driven priority chain.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cpu_response_bank_q <= '0;
      dma_response_bank_q <= '0;
      cpu_response_we_q   <= 1'b0;
    end else begin
      if (cpu_req_ready_o) begin
        cpu_response_bank_q <= cpu_bank_sel;
        cpu_response_we_q   <= cpu_req_we_i;
      end
      if (dma_req_ready_o)
        dma_response_bank_q <= dma_bank_sel;
    end
  end

  assign cpu_resp_valid = cpu_resp_valid_by_bank[cpu_response_bank_q];
  assign cpu_resp_rdata = cpu_resp_rdata_by_bank[cpu_response_bank_q];
  assign cpu_resp_err = cpu_resp_err_by_bank[cpu_response_bank_q];
  assign dma_resp_valid_o = dma_resp_valid_by_bank[dma_response_bank_q];
  assign dma_resp_rdata_o = dma_resp_rdata_by_bank[dma_response_bank_q];
  assign dma_resp_err_o = dma_resp_err_by_bank[dma_response_bank_q];

  generate
    if (SYS_SRAM_LOAD_BYPASS_P) begin : g_cpu_load_bypass
      assign cpu_resp_valid_o = cpu_resp_valid;
      assign cpu_resp_rdata_o = cpu_resp_rdata;
      assign cpu_resp_err_o   = cpu_resp_err;
    end else begin : g_cpu_load_register
      logic        load_resp_valid_q;
      logic [31:0] load_resp_rdata_q;
      logic        load_resp_err_q;

      // Stores preserve their existing response latency. Loads cross a
      // registered boundary after the eight-bank mux, separating the BRAM
      // output path from core branch resolution and instruction fetch.
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          load_resp_valid_q <= 1'b0;
          load_resp_rdata_q <= 32'h0000_0000;
          load_resp_err_q   <= 1'b0;
        end else begin
          load_resp_valid_q <= cpu_resp_valid && !cpu_response_we_q;
          if (cpu_resp_valid && !cpu_response_we_q) begin
            load_resp_rdata_q <= cpu_resp_rdata;
            load_resp_err_q   <= cpu_resp_err;
          end
        end
      end

      assign cpu_resp_valid_o = load_resp_valid_q ||
                                (cpu_resp_valid && cpu_response_we_q);
      // Stores do not return read data. Keep the raw SRAM output completely
      // behind the load-response register so synthesis cannot rebuild the
      // System SRAM-to-core combinational path.
      assign cpu_resp_rdata_o = load_resp_rdata_q;
      assign cpu_resp_err_o = load_resp_valid_q ? load_resp_err_q :
                                                  cpu_resp_err;
    end
  endgenerate

  for (genvar bank = 0; bank < NUM_BANKS; bank++) begin : gen_bank
    system_sram_arbiter arbiter_i (
      .clk              (clk),
      .rst_n            (rst_n),
      .cpu_req_valid_i  (cpu_req_valid_i && (cpu_bank_sel == bank)),
      .cpu_req_we_i     (cpu_req_we_i),
      .cpu_req_be_i     (cpu_req_be_i),
      .cpu_req_addr_i   (cpu_req_addr_i),
      .cpu_req_wdata_i  (cpu_req_wdata_i),
      .cpu_req_ready_o  (cpu_req_ready_by_bank[bank]),
      .cpu_resp_valid_o (cpu_resp_valid_by_bank[bank]),
      .cpu_resp_rdata_o (cpu_resp_rdata_by_bank[bank]),
      .cpu_resp_err_o   (cpu_resp_err_by_bank[bank]),
      .dma_req_valid_i  (dma_req_valid_i && (dma_bank_sel == bank)),
      .dma_req_we_i     (dma_req_we_i),
      .dma_req_be_i     (dma_req_be_i),
      .dma_req_addr_i   (dma_req_addr_i),
      .dma_req_wdata_i  (dma_req_wdata_i),
      .dma_req_ready_o  (dma_req_ready_by_bank[bank]),
      .dma_resp_valid_o (dma_resp_valid_by_bank[bank]),
      .dma_resp_rdata_o (dma_resp_rdata_by_bank[bank]),
      .dma_resp_err_o   (dma_resp_err_by_bank[bank]),
      .sram_req_valid_o (bank_req_valid[bank]),
      .sram_req_we_o    (bank_req_we[bank]),
      .sram_req_be_o    (bank_req_be[bank]),
      .sram_req_addr_o  (bank_req_addr[bank]),
      .sram_req_wdata_o (bank_req_wdata[bank]),
      .sram_resp_valid_i(bank_resp_valid[bank]),
      .sram_resp_rdata_i(bank_resp_rdata[bank]),
      .sram_resp_err_i  (bank_resp_err[bank])
    );

    assign bank_word_addr[bank] = bank_req_addr[bank][BANK_ADDR_LSB +: BANK_ADDR_WIDTH];

    system_sram #(
      .ADDR_WIDTH  (BANK_ADDR_WIDTH),
      .READ_LATENCY(1)
    ) system_sram_i (
      .clk          (clk),
      .rst_n        (rst_n),
      .req_valid_i  (bank_req_valid[bank]),
      .req_we_i     (bank_req_we[bank]),
      .req_be_i     (bank_req_be[bank]),
      .req_addr_i   (bank_word_addr[bank]),
      .req_wdata_i  (bank_req_wdata[bank]),
      .resp_valid_o (bank_resp_valid[bank]),
      .resp_rdata_o (bank_resp_rdata[bank]),
      .resp_err_o   (bank_resp_err[bank])
    );
  end

endmodule
