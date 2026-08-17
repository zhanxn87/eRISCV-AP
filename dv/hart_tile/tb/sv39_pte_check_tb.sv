// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

import riscv_pkg::*;
import sv39_pkg::*;

module sv39_pte_check_tb;
  xlen_t vaddr;
  xlen_t pte;
  logic [1:0] level;
  privilege_mode_e privilege_mode;
  sv39_access_e access;
  logic sum;
  logic mxr;
  logic cbo;
  logic canonical;
  logic pte_valid;
  logic pte_leaf;
  logic ppn_in_range;
  logic superpage_aligned;
  logic permission_ok;
  xlen_t ad_update_mask;
  logic fault;
  paddr_t paddr;

  sv39_pte_check dut (
    .vaddr_i(vaddr),
    .pte_i(pte),
    .level_i(level),
    .privilege_i(privilege_mode),
    .access_i(access),
    .cbo_i(cbo),
    .sum_i(sum),
    .mxr_i(mxr),
    .canonical_o(canonical),
    .pte_valid_o(pte_valid),
    .pte_leaf_o(pte_leaf),
    .ppn_in_range_o(ppn_in_range),
    .superpage_aligned_o(superpage_aligned),
    .permission_ok_o(permission_ok),
    .ad_update_mask_o(ad_update_mask),
    .fault_o(fault),
    .paddr_o(paddr)
  );

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

  task automatic check(input logic condition, input string message);
    if (!condition)
      $fatal(1, "SV39_PTE_CHECK_TB: %s", message);
  endtask

  initial begin
    vaddr = 64'h0000_0000_1234_5678;
    level = 2'd0;
    privilege_mode = PRIV_S;
    access = SV39_ACCESS_LOAD;
    sum = 1'b0;
    mxr = 1'b0;
    cbo = 1'b0;

    pte = make_pte(44'h0000_01234, 1'b1, 1'b1, 1'b0, 1'b0, 1'b1, 1'b1);
    #1;
    check(canonical && pte_valid && pte_leaf && permission_ok && !fault &&
          (ad_update_mask == '0), "valid S-mode RW leaf was rejected");
    check(paddr == 48'h0000_01234_678, "level-0 physical address is wrong");

    access = SV39_ACCESS_FETCH;
    pte = make_pte(44'h0000_01234, 1'b0, 1'b0, 1'b1, 1'b1, 1'b1, 1'b0);
    #1;
    check(fault && !permission_ok, "S-mode fetched an inaccessible U page");

    access = SV39_ACCESS_LOAD;
    sum = 1'b1;
    mxr = 1'b1;
    #1;
    check(!fault && permission_ok, "SUM+MXR load from executable U page failed");

    access = SV39_ACCESS_STORE;
    pte = make_pte(44'h0000_01234, 1'b1, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0);
    sum = 1'b0;
    mxr = 1'b0;
    #1;
    check(!fault && permission_ok && (ad_update_mask == xlen_t'(8'h80)),
          "dirty-bit-clear store did not request a D update");

    cbo = 1'b1;
    #1;
    check(!fault && permission_ok && (ad_update_mask == '0),
          "CBO on an accessed PTE incorrectly requested a D update");
    pte = make_pte(44'h0000_01234, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0);
    #1;
    check(!fault && permission_ok && (ad_update_mask == xlen_t'(8'h40)),
          "CBO did not request only an A update");
    cbo = 1'b0;

    access = SV39_ACCESS_LOAD;
    pte = make_pte(44'h0000_01234, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    #1;
    check(!fault && permission_ok && (ad_update_mask == xlen_t'(8'h40)),
          "accessed-bit-clear load did not request an A update");

    access = SV39_ACCESS_LOAD;
    level = 2'd1;
    pte = make_pte(44'h0000_01235, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);
    #1;
    check(fault && !superpage_aligned, "misaligned megapage leaf did not fault");

    vaddr = 64'h0000_0080_0000_0000;
    level = 2'd0;
    pte = make_pte(44'h0000_01234, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);
    #1;
    check(fault && !canonical, "non-canonical Sv39 address did not fault");

    $display("SV39_PTE_CHECK_TB PASS: canonical, permission, A/D updates, and superpage checks");
    $finish;
  end
endmodule
