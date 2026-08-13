// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Registered two-master System SRAM arbiter.  CPU and DMA use valid/ready
// admission; grant ownership and response routing are fully registered.
module system_sram_arbiter (
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
  output logic        dma_resp_err_o,

  output logic        sram_req_valid_o,
  output logic        sram_req_we_o,
  output logic [3:0]  sram_req_be_o,
  output logic [31:0] sram_req_addr_o,
  output logic [31:0] sram_req_wdata_o,
  input  logic        sram_resp_valid_i,
  input  logic [31:0] sram_resp_rdata_i,
  input  logic        sram_resp_err_i
);

  typedef enum logic [1:0] {ARB_IDLE, ARB_REQUEST, ARB_RESPONSE} arb_state_e;
  arb_state_e state_q;
  logic last_grant_dma_q;
  logic owner_dma_q;
  logic selected_dma;
  logic req_we_q;
  logic [3:0] req_be_q;
  logic [31:0] req_addr_q;
  logic [31:0] req_wdata_q;

  always_comb begin
    selected_dma = dma_req_valid_i && (!cpu_req_valid_i || !last_grant_dma_q);
    cpu_req_ready_o = (state_q == ARB_IDLE) && cpu_req_valid_i && !selected_dma;
    dma_req_ready_o = (state_q == ARB_IDLE) && dma_req_valid_i && selected_dma;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ARB_IDLE;
      last_grant_dma_q <= 1'b1;
      owner_dma_q <= 1'b0;
      req_we_q <= 1'b0;
      req_be_q <= '0;
      req_addr_q <= '0;
      req_wdata_q <= '0;
    end else begin
      unique case (state_q)
        ARB_IDLE: begin
          if (cpu_req_ready_o || dma_req_ready_o) begin
            owner_dma_q <= selected_dma;
            last_grant_dma_q <= selected_dma;
            req_we_q <= selected_dma ? dma_req_we_i : cpu_req_we_i;
            req_be_q <= selected_dma ? dma_req_be_i : cpu_req_be_i;
            req_addr_q <= selected_dma ? dma_req_addr_i : cpu_req_addr_i;
            req_wdata_q <= selected_dma ? dma_req_wdata_i : cpu_req_wdata_i;
            state_q <= ARB_REQUEST;
          end
        end
        ARB_REQUEST: state_q <= ARB_RESPONSE;
        ARB_RESPONSE: begin
          if (sram_resp_valid_i)
            state_q <= ARB_IDLE;
        end
        default: state_q <= ARB_IDLE;
      endcase
    end
  end

  assign sram_req_valid_o = (state_q == ARB_REQUEST);
  assign sram_req_we_o = req_we_q;
  assign sram_req_be_o = req_be_q;
  assign sram_req_addr_o = req_addr_q;
  assign sram_req_wdata_o = req_wdata_q;

  assign cpu_resp_valid_o = (state_q == ARB_RESPONSE) && sram_resp_valid_i && !owner_dma_q;
  assign cpu_resp_rdata_o = sram_resp_rdata_i;
  assign cpu_resp_err_o = cpu_resp_valid_o && sram_resp_err_i;
  assign dma_resp_valid_o = (state_q == ARB_RESPONSE) && sram_resp_valid_i && owner_dma_q;
  assign dma_resp_rdata_o = sram_resp_rdata_i;
  assign dma_resp_err_o = dma_resp_valid_o && sram_resp_err_i;

endmodule
