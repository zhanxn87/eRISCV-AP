// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

import riscv_pkg::*;
import sv39_pkg::*;

module sv39_tlb_tb;
  logic clk;
  logic rst_n;
  logic lookup_valid;
  xlen_t lookup_vaddr;
  logic [15:0] lookup_asid;
  privilege_mode_e lookup_privilege;
  sv39_access_e lookup_access;
  logic lookup_sum;
  logic lookup_mxr;
  logic lookup_hit;
  logic lookup_fault;
  xlen_t lookup_ad_update_mask;
  paddr_t lookup_paddr;
  logic refill_valid;
  xlen_t refill_vaddr;
  logic [15:0] refill_asid;
  xlen_t refill_pte;
  logic [1:0] refill_level;
  logic flush_valid;
  xlen_t flush_vaddr;
  logic [15:0] flush_asid;

  sv39_tlb #(.ENTRIES_P(4)) dut (
    .clk(clk),
    .rst_n(rst_n),
    .lookup_valid_i(lookup_valid),
    .lookup_vaddr_i(lookup_vaddr),
    .lookup_asid_i(lookup_asid),
    .lookup_privilege_i(lookup_privilege),
    .lookup_access_i(lookup_access),
    .lookup_sum_i(lookup_sum),
    .lookup_mxr_i(lookup_mxr),
    .lookup_hit_o(lookup_hit),
    .lookup_fault_o(lookup_fault),
    .lookup_ad_update_mask_o(lookup_ad_update_mask),
    .lookup_paddr_o(lookup_paddr),
    .refill_valid_i(refill_valid),
    .refill_vaddr_i(refill_vaddr),
    .refill_asid_i(refill_asid),
    .refill_pte_i(refill_pte),
    .refill_level_i(refill_level),
    .flush_valid_i(flush_valid),
    .flush_vaddr_i(flush_vaddr),
    .flush_asid_i(flush_asid)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  function automatic xlen_t make_pte(
    input logic [43:0] ppn,
    input logic r,
    input logic w,
    input logic x,
    input logic u,
    input logic global,
    input logic a,
    input logic d
  );
    make_pte = (xlen_t'(ppn) << 10) |
               xlen_t'({54'd0, 2'b00, d, a, global, u, x, w, r, 1'b1});
  endfunction

  task automatic check(input logic condition, input string message);
    if (!condition)
      $fatal(1, "SV39_TLB_TB: %s", message);
  endtask

  task automatic fill(input xlen_t va, input logic [15:0] asid,
                      input xlen_t pte, input logic [1:0] level);
    begin
      refill_vaddr = va;
      refill_asid = asid;
      refill_pte = pte;
      refill_level = level;
      refill_valid = 1'b1;
      @(posedge clk);
      #1 refill_valid = 1'b0;
    end
  endtask

  task automatic lookup(input xlen_t va, input logic [15:0] asid,
                        input privilege_mode_e privilege, input sv39_access_e access,
                        input logic expected_hit, input logic expected_fault,
                        input xlen_t expected_ad_update_mask,
                        input paddr_t expected_paddr);
    begin
      lookup_vaddr = va;
      lookup_asid = asid;
      lookup_privilege = privilege;
      lookup_access = access;
      lookup_valid = 1'b1;
      #1;
      check(lookup_hit == expected_hit, "unexpected lookup hit result");
      check(lookup_fault == expected_fault, "unexpected lookup fault result");
      check(lookup_ad_update_mask == expected_ad_update_mask,
            "unexpected TLB A/D update request");
      if (expected_hit && !expected_fault)
        check(lookup_paddr == expected_paddr, "unexpected lookup physical address");
      lookup_valid = 1'b0;
    end
  endtask

  task automatic sfence(input xlen_t va, input logic [15:0] asid);
    begin
      flush_vaddr = va;
      flush_asid = asid;
      flush_valid = 1'b1;
      @(posedge clk);
      #1 flush_valid = 1'b0;
    end
  endtask

  initial begin
    rst_n = 1'b0;
    lookup_valid = 1'b0;
    lookup_vaddr = '0;
    lookup_asid = '0;
    lookup_privilege = PRIV_S;
    lookup_access = SV39_ACCESS_LOAD;
    lookup_sum = 1'b0;
    lookup_mxr = 1'b0;
    refill_valid = 1'b0;
    refill_vaddr = '0;
    refill_asid = '0;
    refill_pte = '0;
    refill_level = '0;
    flush_valid = 1'b0;
    flush_vaddr = '0;
    flush_asid = '0;
    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    fill(64'h0000_0000_4123_4567, 16'h11,
         make_pte(44'h45, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1), 2'd0);
    lookup(64'h0000_0000_4123_4abc, 16'h11, PRIV_S, SV39_ACCESS_LOAD,
           1'b1, 1'b0, '0, 48'h0000_0004_5abc);
    lookup(64'h0000_0000_4123_4abc, 16'h12, PRIV_S, SV39_ACCESS_LOAD,
           1'b0, 1'b0, '0, '0);

    fill(64'h0000_0000_5223_4567, 16'h22,
         make_pte(44'h46, 1'b1, 1'b0, 1'b1, 1'b1, 1'b1, 1'b1, 1'b0), 2'd0);
    lookup(64'h0000_0000_5223_4abc, 16'h99, PRIV_S, SV39_ACCESS_LOAD,
           1'b1, 1'b1, '0, '0);
    lookup_sum = 1'b1;
    lookup_mxr = 1'b1;
    lookup(64'h0000_0000_5223_4abc, 16'h99, PRIV_S, SV39_ACCESS_LOAD,
           1'b1, 1'b0, '0, 48'h0000_0004_6abc);
    lookup_sum = 1'b0;
    lookup_mxr = 1'b0;

    fill(64'h0000_0000_6123_4567, 16'h44,
         make_pte(44'h47, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0), 2'd0);
    lookup(64'h0000_0000_6123_4abc, 16'h44, PRIV_S, SV39_ACCESS_STORE,
           1'b1, 1'b0, xlen_t'(8'h80), 48'h0000_0004_7abc);

    fill(64'h0000_0000_8123_4567, 16'h33,
         make_pte(44'h0004_0000, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0), 2'd2);
    lookup(64'h0000_0000_8123_4abc, 16'h33, PRIV_S, SV39_ACCESS_LOAD,
           1'b1, 1'b0, '0, 48'h0000_4123_4abc);

    // VA+ASID invalidates only that non-global translation.
    sfence(64'h0000_0000_4123_4000, 16'h11);
    lookup(64'h0000_0000_4123_4abc, 16'h11, PRIV_S, SV39_ACCESS_LOAD,
           1'b0, 1'b0, '0, '0);
    lookup(64'h0000_0000_6123_4abc, 16'h44, PRIV_S, SV39_ACCESS_STORE,
           1'b1, 1'b0, xlen_t'(8'h80), 48'h0000_0004_7abc);

    // ASID-qualified SFENCE.VMA keeps global mappings; ASID=0 removes them.
    sfence(64'h0000_0000_5223_4000, 16'h22);
    lookup_sum = 1'b1;
    lookup_mxr = 1'b1;
    lookup(64'h0000_0000_5223_4abc, 16'h99, PRIV_S, SV39_ACCESS_LOAD,
           1'b1, 1'b0, '0, 48'h0000_0004_6abc);
    sfence(64'h0000_0000_5223_4000, '0);
    lookup(64'h0000_0000_5223_4abc, 16'h99, PRIV_S, SV39_ACCESS_LOAD,
           1'b0, 1'b0, '0, '0);
    lookup_sum = 1'b0;
    lookup_mxr = 1'b0;

    sfence('0, '0);
    lookup(64'h0000_0000_8123_4abc, 16'h33, PRIV_S, SV39_ACCESS_LOAD,
           1'b0, 1'b0, '0, '0);

    $display("SV39_TLB_TB PASS: ASID/global, A/D, superpages, and selective SFENCE.VMA");
    $finish;
  end
endmodule
