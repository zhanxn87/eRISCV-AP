// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Core-only CLINT plus PLIC-style external-interrupt MMIO shim.
// It keeps local interrupt state outside riscv_core so ACT tests can exercise
// machine software, timer, and external interrupt plumbing without a full SoC.
// The ACT external-signal register is not a complete PLIC implementation.
module clint_plic_mmio #(
  parameter int READ_LATENCY = 1,
  parameter int ADDR_WIDTH = 48,
  parameter int DATA_WIDTH = 64,
  parameter int BYTE_LANES = DATA_WIDTH / 8
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        req_i,
  input  logic        we_i,
  input  logic [BYTE_LANES-1:0] be_i,
  input  logic [ADDR_WIDTH-1:0] addr_i,
  input  logic [DATA_WIDTH-1:0] wdata_i,
  output logic        hit_o,
  output logic        resp_valid_o,
  output logic [DATA_WIDTH-1:0] rdata_o,
  output logic        err_o,
  output logic [63:0] mtime_o,
  output logic [31:0] irq_o
);

  localparam logic [ADDR_WIDTH-1:0] MSIP_ADDR          = ADDR_WIDTH'(32'h0200_0000);
  localparam logic [ADDR_WIDTH-1:0] MTIMECMP_LO_ADDR   = ADDR_WIDTH'(32'h0200_4000);
  localparam logic [ADDR_WIDTH-1:0] MTIME_LO_ADDR      = ADDR_WIDTH'(32'h0200_bff8);
  localparam logic [ADDR_WIDTH-1:0] ACT_EXTSIG_ADDR    = ADDR_WIDTH'(32'h0c00_0004);
  localparam logic [31:0] ACT_EXTSIG_SET_MSK = 32'h7fff_ffff;

  logic        msip_q;
  logic [63:0] mtime_q;
  logic [63:0] mtimecmp_q;
  logic [31:0] act_irq_pending_q;
  logic [DATA_WIDTH-1:0] read_data_q [0:READ_LATENCY-1];
  logic [READ_LATENCY-1:0] valid_pipe_q;
  logic [DATA_WIDTH-1:0] read_data_d;
  logic [ADDR_WIDTH-1:0] aligned_addr;
  logic        msip_hit;
  logic        mtimecmp_hit;
  logic        mtime_hit;
  logic        act_extsig_hit;
  logic        req_hit;
  logic [63:0] mtime_n;
  logic [63:0] mtimecmp_n;
  logic [31:0] act_irq_pending_n;
  logic        msip_n;
  integer index;

  logic [31:0] act_write_data;
  logic [3:0]  act_write_be;

  function automatic logic [63:0] apply_byte_enables(
    input logic [63:0] current_value,
    input logic [63:0] write_value,
    input logic [7:0]  byte_enables
  );
    logic [63:0] merged;
    int unsigned byte_index;
    begin
      merged = current_value;
      for (byte_index = 0; byte_index < 8; byte_index++) begin
        if (byte_enables[byte_index]) begin
          merged[byte_index*8 +: 8] = write_value[byte_index*8 +: 8];
        end
      end
      apply_byte_enables = merged;
    end
  endfunction

  function automatic logic [31:0] apply_word_byte_enables(
    input logic [31:0] current_value,
    input logic [31:0] write_value,
    input logic [3:0]  byte_enables
  );
    logic [31:0] merged;
    int unsigned byte_index;
    begin
      merged = current_value;
      for (byte_index = 0; byte_index < 4; byte_index++) begin
        if (byte_enables[byte_index]) begin
          merged[byte_index*8 +: 8] = write_value[byte_index*8 +: 8];
        end
      end
      apply_word_byte_enables = merged;
    end
  endfunction

  assign aligned_addr    = {addr_i[ADDR_WIDTH-1:3], 3'b000};
  assign msip_hit        = (aligned_addr == MSIP_ADDR);
  assign mtimecmp_hit    = (aligned_addr == MTIMECMP_LO_ADDR);
  assign mtime_hit       = (aligned_addr == MTIME_LO_ADDR);
  assign act_extsig_hit = (addr_i == ACT_EXTSIG_ADDR);
  assign hit_o          = msip_hit | mtimecmp_hit | mtime_hit | act_extsig_hit;
  assign req_hit        = req_i & hit_o;
  assign err_o          = 1'b0;
  assign act_write_data = addr_i[2] ? wdata_i[63:32] : wdata_i[31:0];
  assign act_write_be   = addr_i[2] ? be_i[7:4] : be_i[3:0];

  always_comb begin
    unique case (1'b1)
      msip_hit:        read_data_d = {63'h0, msip_q};
      mtimecmp_hit:    read_data_d = mtimecmp_q;
      mtime_hit:       read_data_d = mtime_q;
      act_extsig_hit:  read_data_d = {act_irq_pending_q, 32'h0000_0000};
      default:         read_data_d = '0;
    endcase
  end

  always_comb begin
    mtime_n = mtime_q + 64'd1;
    mtimecmp_n = mtimecmp_q;
    act_irq_pending_n = act_irq_pending_q;
    msip_n = msip_q;

    if (req_hit && we_i) begin
      if (msip_hit) begin
        msip_n = apply_byte_enables({63'h0, msip_q}, wdata_i, be_i) != 64'h0;
      end
      if (mtimecmp_hit) begin
        mtimecmp_n = apply_byte_enables(mtimecmp_q, wdata_i, be_i);
      end
      if (mtime_hit) begin
        mtime_n = apply_byte_enables(mtime_q, wdata_i, be_i);
      end
      if (act_extsig_hit) begin
        if (act_write_be != 4'h0 && act_write_data[31]) begin
          act_irq_pending_n = act_irq_pending_q |
                              (apply_word_byte_enables('0, act_write_data, act_write_be) & ACT_EXTSIG_SET_MSK);
        end else begin
          act_irq_pending_n = act_irq_pending_q &
                              ~(apply_word_byte_enables('0, act_write_data, act_write_be) & ACT_EXTSIG_SET_MSK);
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      msip_q <= 1'b0;
      mtime_q <= 64'h0000_0000_0000_0000;
      mtimecmp_q <= 64'hffff_ffff_ffff_ffff;
      act_irq_pending_q <= 32'h0000_0000;
      valid_pipe_q <= '0;
      for (index = 0; index < READ_LATENCY; index = index + 1) begin
        read_data_q[index] <= '0;
      end
    end else begin
      msip_q <= msip_n;
      mtime_q <= mtime_n;
      mtimecmp_q <= mtimecmp_n;
      act_irq_pending_q <= act_irq_pending_n;
      valid_pipe_q[0] <= req_hit;
      read_data_q[0] <= read_data_d;
      for (index = 1; index < READ_LATENCY; index = index + 1) begin
        valid_pipe_q[index] <= valid_pipe_q[index-1];
        read_data_q[index] <= read_data_q[index-1];
      end
    end
  end

  assign resp_valid_o = valid_pipe_q[READ_LATENCY-1];
  assign rdata_o = read_data_q[READ_LATENCY-1];
  assign mtime_o = mtime_q;

  always_comb begin
    irq_o = 32'h0000_0000;
    irq_o[3] = msip_q;
    irq_o[7] = (mtime_q >= mtimecmp_q);
    irq_o[11] = act_irq_pending_q[11];
  end

endmodule
