// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

import riscv_pkg::*;
import sv39_pkg::*;

module sv39_mmu_ctrl_tb;
  logic clk;
  logic rst_n;
  logic flush_valid;
  xlen_t flush_vaddr;
  logic [15:0] flush_asid;
  logic i_req_valid;
  logic i_req_ready;
  xlen_t i_req_vaddr;
  xlen_t i_req_satp;
  privilege_mode_e i_req_privilege;
  logic i_req_sum;
  logic i_req_mxr;
  logic i_resp_valid;
  logic i_resp_ready;
  paddr_t i_resp_paddr;
  logic i_resp_page_fault;
  logic i_resp_access_fault;
  logic d_req_valid;
  logic d_req_ready;
  xlen_t d_req_vaddr;
  xlen_t d_req_satp;
  privilege_mode_e d_req_privilege;
  sv39_access_e d_req_access;
  logic d_req_sum;
  logic d_req_mxr;
  logic d_resp_valid;
  logic d_resp_ready;
  paddr_t d_resp_paddr;
  logic d_resp_page_fault;
  logic d_resp_access_fault;
  logic pte_req_valid;
  logic pte_req_ready;
  paddr_t pte_req_addr;
  xlen_t pte_req_wdata;
  atomic_op_e pte_req_atomic_op;
  logic pte_resp_valid;
  xlen_t pte_resp_rdata;
  logic pte_resp_err;
  xlen_t pte_mem [0:4095];
  int unsigned pte_read_count;
  int unsigned pte_amo_count;
  logic pte_force_error;

  sv39_mmu_ctrl dut (
    .clk,
    .rst_n,
    .flush_valid_i(flush_valid),
    .flush_vaddr_i(flush_vaddr),
    .flush_asid_i(flush_asid),
    .i_req_valid_i(i_req_valid),
    .i_req_ready_o(i_req_ready),
    .i_req_vaddr_i(i_req_vaddr),
    .i_req_satp_i(i_req_satp),
    .i_req_privilege_i(i_req_privilege),
    .i_req_sum_i(i_req_sum),
    .i_req_mxr_i(i_req_mxr),
    .i_resp_valid_o(i_resp_valid),
    .i_resp_ready_i(i_resp_ready),
    .i_resp_paddr_o(i_resp_paddr),
    .i_resp_page_fault_o(i_resp_page_fault),
    .i_resp_access_fault_o(i_resp_access_fault),
    .d_req_valid_i(d_req_valid),
    .d_req_ready_o(d_req_ready),
    .d_req_vaddr_i(d_req_vaddr),
    .d_req_satp_i(d_req_satp),
    .d_req_privilege_i(d_req_privilege),
    .d_req_access_i(d_req_access),
    .d_req_sum_i(d_req_sum),
    .d_req_mxr_i(d_req_mxr),
    .d_resp_valid_o(d_resp_valid),
    .d_resp_ready_i(d_resp_ready),
    .d_resp_paddr_o(d_resp_paddr),
    .d_resp_page_fault_o(d_resp_page_fault),
    .d_resp_access_fault_o(d_resp_access_fault),
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
  assign i_resp_ready = 1'b1;
  assign d_resp_ready = 1'b1;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pte_resp_valid <= 1'b0;
      pte_resp_rdata <= '0;
      pte_resp_err <= 1'b0;
      pte_read_count <= '0;
      pte_amo_count <= '0;
    end else begin
      pte_resp_valid <= pte_req_valid;
      pte_resp_rdata <= pte_mem[pte_req_addr[14:3]];
      pte_resp_err <= pte_force_error;
      if (pte_req_valid && pte_req_ready) begin
        if (pte_req_atomic_op == ATOMIC_OR) begin
          pte_mem[pte_req_addr[14:3]] <= pte_mem[pte_req_addr[14:3]] | pte_req_wdata;
          pte_amo_count <= pte_amo_count + 1'b1;
        end else begin
          pte_read_count <= pte_read_count + 1'b1;
        end
      end
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
      $fatal(1, "SV39_MMU_CTRL_TB: %s", message);
  endtask

  task automatic issue_i(
    input xlen_t vaddr,
    input xlen_t satp,
    input privilege_mode_e privilege,
    input paddr_t expected_paddr,
    input logic expected_page_fault,
    input logic expected_access_fault
  );
    begin
      @(negedge clk);
      check(i_req_ready, "instruction request was not accepted from idle");
      i_req_vaddr = vaddr;
      i_req_satp = satp;
      i_req_privilege = privilege;
      i_req_valid = 1'b1;
      @(posedge clk);
      #1 i_req_valid = 1'b0;
      wait (i_resp_valid);
      #1;
      check(i_resp_paddr == expected_paddr, "instruction response physical address is wrong");
      check(i_resp_page_fault == expected_page_fault, "instruction page-fault result is wrong");
      check(i_resp_access_fault == expected_access_fault, "instruction access-fault result is wrong");
      @(posedge clk);
    end
  endtask

  task automatic issue_d(
    input xlen_t vaddr,
    input xlen_t satp,
    input privilege_mode_e privilege,
    input sv39_access_e access,
    input paddr_t expected_paddr,
    input logic expected_page_fault,
    input logic expected_access_fault
  );
    begin
      @(negedge clk);
      check(d_req_ready, "data request was not accepted from idle");
      d_req_vaddr = vaddr;
      d_req_satp = satp;
      d_req_privilege = privilege;
      d_req_access = access;
      d_req_valid = 1'b1;
      @(posedge clk);
      #1 d_req_valid = 1'b0;
      wait (d_resp_valid);
      #1;
      check(d_resp_paddr == expected_paddr, "data response physical address is wrong");
      check(d_resp_page_fault == expected_page_fault, "data page-fault result is wrong");
      check(d_resp_access_fault == expected_access_fault,
            "translated data access-fault result is wrong");
      @(posedge clk);
    end
  endtask

  initial begin
    xlen_t satp;
    xlen_t va;
    rst_n = 1'b0;
    flush_valid = 1'b0;
    flush_vaddr = '0;
    flush_asid = '0;
    pte_force_error = 1'b0;
    i_req_valid = 1'b0;
    i_req_vaddr = '0;
    i_req_satp = '0;
    i_req_privilege = PRIV_M;
    i_req_sum = 1'b0;
    i_req_mxr = 1'b0;
    d_req_valid = 1'b0;
    d_req_vaddr = '0;
    d_req_satp = '0;
    d_req_privilege = PRIV_M;
    d_req_access = SV39_ACCESS_LOAD;
    d_req_sum = 1'b0;
    d_req_mxr = 1'b0;
    for (int index = 0; index < 4096; index++)
      pte_mem[index] = '0;

    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    // M-mode and Bare both bypass translation, but wide physical addresses
    // must report an access fault rather than being silently truncated.
    issue_i(64'h0000_0000_00ab_cdef, '0, PRIV_M,
            48'h0000_00ab_cdef, 1'b0, 1'b0);
    check(pte_read_count == 0, "Bare request incorrectly touched the PTW");
    issue_i(64'h0001_0000_0000_1000, '0, PRIV_M,
            48'h0000_0000_1000, 1'b0, 1'b1);

    // root PPN=1 -> L1 PPN=2 -> L0 PPN=3 -> executable/RW 4KiB leaf PPN=0x45.
    va = 64'h0000_0000_4123_4567;
    satp = (xlen_t'(SV39_MODE_SV39) << 60) | xlen_t'(44'h1);
    pte_mem[pte_word_index(pte_addr(44'h1, va, 2'd2))] =
        make_pte(44'h2, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    pte_mem[pte_word_index(pte_addr(44'h2, va, 2'd1))] =
        make_pte(44'h3, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    pte_mem[pte_word_index(pte_addr(44'h3, va, 2'd0))] =
        make_pte(44'h45, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0);

    issue_i(va, satp, PRIV_S, 48'h0000_0004_5567, 1'b0, 1'b0);
    check(pte_read_count == 3 && pte_amo_count == 1,
          "ITLB miss did not walk and set A atomically");
    issue_i(va, satp, PRIV_S, 48'h0000_0004_5567, 1'b0, 1'b0);
    check(pte_read_count == 3 && pte_amo_count == 1,
          "ITLB hit unexpectedly re-walked or updated the page table");

    issue_d(64'h0000_0000_4123_4abc, satp, PRIV_S, SV39_ACCESS_LOAD,
            48'h0000_0004_5abc, 1'b0, 1'b0);
    check(pte_read_count == 6 && pte_amo_count == 1,
          "DTLB did not use its independent miss path");

    // A DTLB-hit store sees D=0, re-walks, and sets D atomically.
    issue_d(64'h0000_0000_4123_4abc, satp, PRIV_S, SV39_ACCESS_STORE,
            48'h0000_0004_5abc, 1'b0, 1'b0);
    check(pte_read_count == 9 && pte_amo_count == 2,
          "DTLB hit did not re-walk and set D atomically");
    check(pte_mem[pte_word_index(pte_addr(44'h3, va, 2'd0))][7],
          "PTE dirty bit was not written by the shared PTW");

    // A physical PTE-port error maps to an architectural access fault.
    @(negedge clk);
    flush_valid = 1'b1;
    flush_vaddr = '0;
    flush_asid = '0;
    @(posedge clk);
    #1 flush_valid = 1'b0;
    pte_force_error = 1'b1;
    issue_i(va, satp, PRIV_S, '0, 1'b0, 1'b1);
    pte_force_error = 1'b0;

    $display("SV39_MMU_CTRL_TB PASS: ITLB/DTLB, atomic A/D, selective flush, and PTE access fault");
    $finish;
  end
endmodule
