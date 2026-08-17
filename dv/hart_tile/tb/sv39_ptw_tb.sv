// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

import riscv_pkg::*;
import sv39_pkg::*;

module sv39_ptw_tb;
  logic clk;
  logic rst_n;
  logic req_valid;
  logic req_ready;
  xlen_t req_vaddr;
  xlen_t req_satp;
  privilege_mode_e req_privilege;
  sv39_access_e req_access;
  logic req_cbo;
  logic req_sum;
  logic req_mxr;
  logic resp_valid;
  logic resp_ready;
  paddr_t resp_paddr;
  logic resp_fault;
  logic resp_access_fault;
  xlen_t resp_pte;
  logic [1:0] resp_level;
  logic pte_req_valid;
  logic pte_req_ready;
  paddr_t pte_req_addr;
  xlen_t pte_req_wdata;
  atomic_op_e pte_req_atomic_op;
  logic pte_resp_valid;
  xlen_t pte_resp_rdata;
  logic pte_resp_err;
  logic [63:0] pte_mem [0:4095];

  sv39_ptw dut (
    .clk,
    .rst_n,
    .req_valid_i(req_valid),
    .req_ready_o(req_ready),
    .req_vaddr_i(req_vaddr),
    .req_satp_i(req_satp),
    .req_privilege_i(req_privilege),
    .req_access_i(req_access),
    .req_cbo_i(req_cbo),
    .req_sum_i(req_sum),
    .req_mxr_i(req_mxr),
    .resp_valid_o(resp_valid),
    .resp_ready_i(resp_ready),
    .resp_paddr_o(resp_paddr),
    .resp_fault_o(resp_fault),
    .resp_access_fault_o(resp_access_fault),
    .resp_pte_o(resp_pte),
    .resp_level_o(resp_level),
    .pte_req_valid_o(pte_req_valid),
    .pte_req_ready_i(pte_req_ready),
    .pte_req_addr_o(pte_req_addr),
    .pte_req_wdata_o(pte_req_wdata),
    .pte_req_atomic_op_o(pte_req_atomic_op),
    .pte_resp_valid_i(pte_resp_valid),
    .pte_resp_rdata_i(pte_resp_rdata),
    .pte_resp_err_i(pte_resp_err)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;
  assign pte_req_ready = 1'b1;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pte_resp_valid <= 1'b0;
      pte_resp_rdata <= '0;
      pte_resp_err <= 1'b0;
    end else begin
      pte_resp_valid <= pte_req_valid;
      pte_resp_rdata <= pte_mem[pte_req_addr[14:3]];
      pte_resp_err <= 1'b0;
      if (pte_req_valid && (pte_req_atomic_op == ATOMIC_OR))
        pte_mem[pte_req_addr[14:3]] <= pte_mem[pte_req_addr[14:3]] | pte_req_wdata;
    end
  end

  function automatic xlen_t make_pte(
    input logic [43:0] ppn,
    input logic r,
    input logic w,
    input logic x,
    input logic u,
    input logic a,
    input logic d
  );
    make_pte = (xlen_t'(ppn) << 10) |
               xlen_t'({54'd0, 2'b00, d, a, 1'b0, u, x, w, r, 1'b1});
  endfunction

  function automatic paddr_t pte_addr(
    input logic [43:0] ppn,
    input xlen_t vaddr,
    input logic [1:0] level
  );
    logic [8:0] index;
    begin
      unique case (level)
        2'd2: index = vaddr[38:30];
        2'd1: index = vaddr[29:21];
        default: index = vaddr[20:12];
      endcase
      return {ppn[35:0], 12'b0} + (paddr_t'(index) << 3);
    end
  endfunction

  function automatic logic [11:0] pte_word_index(input paddr_t addr);
    return addr[14:3];
  endfunction

  task automatic check(input logic condition, input string message);
    if (!condition)
      $fatal(1, "SV39_PTW_TB: %s", message);
  endtask

  task automatic walk(input xlen_t vaddr, input logic expected_fault,
                      input paddr_t expected_paddr, input logic [1:0] expected_level);
    begin
      @(negedge clk);
      check(req_ready, "PTW did not return to idle before next request");
      req_vaddr = vaddr;
      req_valid = 1'b1;
      @(posedge clk);
      #1;
      req_valid = 1'b0;
      wait (resp_valid);
      #1;
      check(resp_fault == expected_fault, "unexpected PTW fault result");
      check(!resp_access_fault, "unexpected PTW access fault");
      check(resp_level == expected_level, "unexpected leaf/fault level");
      if (!expected_fault)
        check(resp_paddr == expected_paddr, "translated physical address is wrong");
      @(posedge clk);
    end
  endtask

  initial begin
    rst_n = 1'b0;
    req_valid = 1'b0;
    req_vaddr = '0;
    req_satp = (xlen_t'(SV39_MODE_SV39) << 60) | xlen_t'(44'h1);
    req_privilege = PRIV_S;
    req_access = SV39_ACCESS_LOAD;
    req_cbo = 1'b0;
    req_sum = 1'b0;
    req_mxr = 1'b0;
    resp_ready = 1'b1;
    for (int index = 0; index < 4096; index++)
      pte_mem[index] = '0;

    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    // root PPN=1 -> L1 PPN=2 -> L0 PPN=3 -> 4KiB leaf PPN=0x45.
    pte_mem[pte_word_index(pte_addr(44'h1, 64'h0000_0000_4123_4567, 2'd2))] =
        make_pte(44'h2, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    pte_mem[pte_word_index(pte_addr(44'h2, 64'h0000_0000_4123_4567, 2'd1))] =
        make_pte(44'h3, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    pte_mem[pte_word_index(pte_addr(44'h3, 64'h0000_0000_4123_4567, 2'd0))] =
        make_pte(44'h45, 1'b1, 1'b1, 1'b0, 1'b0, 1'b1, 1'b1);
    walk(64'h0000_0000_4123_4567, 1'b0, 48'h0000_0004_5567, 2'd0);

    // A clean store updates D atomically instead of faulting.
    req_access = SV39_ACCESS_STORE;
    pte_mem[pte_word_index(pte_addr(44'h3, 64'h0000_0000_4123_4567, 2'd0))] =
        make_pte(44'h45, 1'b1, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0);
    walk(64'h0000_0000_4123_4567, 1'b0, 48'h0000_0004_5567, 2'd0);
    check(pte_mem[pte_word_index(pte_addr(44'h3, 64'h0000_0000_4123_4567, 2'd0))][7],
          "PTW did not set the dirty bit atomically");

    // CBO follows store permissions but must set only A, never D.
    req_cbo = 1'b1;
    pte_mem[pte_word_index(pte_addr(44'h3, 64'h0000_0000_4123_4567, 2'd0))] =
        make_pte(44'h45, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0);
    walk(64'h0000_0000_4123_4567, 1'b0, 48'h0000_0004_5567, 2'd0);
    check(pte_mem[pte_word_index(pte_addr(44'h3, 64'h0000_0000_4123_4567, 2'd0))][6] &&
          !pte_mem[pte_word_index(pte_addr(44'h3, 64'h0000_0000_4123_4567, 2'd0))][7],
          "PTW CBO did not set only PTE.A");
    req_cbo = 1'b0;

    // A 1GiB root-level leaf returns level 2 and incorporates VPN[1:0].
    req_access = SV39_ACCESS_LOAD;
    for (int index = 0; index < 4096; index++)
      pte_mem[index] = '0;
    pte_mem[pte_word_index(pte_addr(44'h1, 64'h0000_0000_4123_4567, 2'd2))] =
        make_pte(44'h0004_0000, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);
    walk(64'h0000_0000_4123_4567, 1'b0, 48'h0000_4123_4567, 2'd2);

    $display("SV39_PTW_TB PASS: three-level walk, atomic A/D update, and gigapage leaf");
    $finish;
  end
endmodule
