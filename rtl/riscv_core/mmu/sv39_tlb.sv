// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

import riscv_pkg::*;
import sv39_pkg::*;

// Fully associative Sv39 translation cache. The same primitive is used for
// ITLB and DTLB; misses are arbitrated by the shared PTW in mmu_ctrl.
module sv39_tlb #(
  parameter int unsigned ENTRIES_P = 16
) (
  input  logic            clk,
  input  logic            rst_n,

  input  logic            lookup_valid_i,
  input  xlen_t           lookup_vaddr_i,
  input  logic [15:0]     lookup_asid_i,
  input  privilege_mode_e lookup_privilege_i,
  input  sv39_access_e    lookup_access_i,
  input  logic            lookup_sum_i,
  input  logic            lookup_mxr_i,
  output logic            lookup_hit_o,
  output logic            lookup_fault_o,
  output xlen_t           lookup_ad_update_mask_o,
  output paddr_t          lookup_paddr_o,

  // PTW fill. The supplied PTE must be a checked Sv39 leaf PTE.
  input  logic            refill_valid_i,
  input  xlen_t           refill_vaddr_i,
  input  logic [15:0]     refill_asid_i,
  input  xlen_t           refill_pte_i,
  input  logic [1:0]      refill_level_i,

  // SFENCE.VMA invalidation selector. A zero virtual address or ASID means
  // all virtual addresses or ASIDs respectively; ASID-qualified flushes keep
  // global mappings as required by the privileged specification.
  input  logic            flush_valid_i,
  input  xlen_t           flush_vaddr_i,
  input  logic [15:0]     flush_asid_i
);
  localparam int unsigned ENTRY_W = (ENTRIES_P > 1) ? $clog2(ENTRIES_P) : 1;

  logic [ENTRIES_P-1:0] valid_q;
  logic [26:0] vpn_q [0:ENTRIES_P-1];
  logic [15:0] asid_q [0:ENTRIES_P-1];
  xlen_t pte_q [0:ENTRIES_P-1];
  logic [1:0] level_q [0:ENTRIES_P-1];
  logic [ENTRY_W-1:0] replace_q;

  logic [26:0] lookup_vpn;
  logic hit_found;
  xlen_t hit_pte;
  logic [1:0] hit_level;
  logic pte_canonical;
  logic pte_valid;
  logic pte_leaf;
  logic ppn_in_range;
  logic superpage_aligned;
  logic permission_ok;
  xlen_t pte_ad_update_mask;
  logic pte_fault;
  logic flush_vaddr_all;
  logic flush_asid_all;
  integer lookup_index;
  integer flush_index;

  function automatic logic vpn_matches(
    input logic [26:0] request_vpn,
    input logic [26:0] entry_vpn,
    input logic [1:0] entry_level
  );
    unique case (entry_level)
      2'd2: return request_vpn[26:18] == entry_vpn[26:18];
      2'd1: return request_vpn[26:9] == entry_vpn[26:9];
      default: return request_vpn == entry_vpn;
    endcase
  endfunction

  assign lookup_vpn = lookup_vaddr_i[38:12];

  always_comb begin
    hit_found = 1'b0;
    hit_pte = '0;
    hit_level = '0;
    for (lookup_index = 0; lookup_index < ENTRIES_P; lookup_index = lookup_index + 1) begin
      if (valid_q[lookup_index] &&
          vpn_matches(lookup_vpn, vpn_q[lookup_index], level_q[lookup_index]) &&
          (pte_q[lookup_index][5] || (asid_q[lookup_index] == lookup_asid_i))) begin
        hit_found = 1'b1;
        hit_pte = pte_q[lookup_index];
        hit_level = level_q[lookup_index];
      end
    end
  end

  sv39_pte_check pte_check_i (
    .vaddr_i(lookup_vaddr_i),
    .pte_i(hit_pte),
    .level_i(hit_level),
    .privilege_i(lookup_privilege_i),
    .access_i(lookup_access_i),
    .sum_i(lookup_sum_i),
    .mxr_i(lookup_mxr_i),
    .canonical_o(pte_canonical),
    .pte_valid_o(pte_valid),
    .pte_leaf_o(pte_leaf),
    .ppn_in_range_o(ppn_in_range),
    .superpage_aligned_o(superpage_aligned),
    .permission_ok_o(permission_ok),
    .ad_update_mask_o(pte_ad_update_mask),
    .fault_o(pte_fault),
    .paddr_o(lookup_paddr_o)
  );

  assign lookup_hit_o = lookup_valid_i && hit_found;
  assign lookup_fault_o = lookup_valid_i && hit_found && pte_fault;
  assign lookup_ad_update_mask_o = (lookup_valid_i && hit_found && !pte_fault) ?
                                   pte_ad_update_mask : '0;
  assign flush_vaddr_all = (flush_vaddr_i == '0);
  assign flush_asid_all = (flush_asid_i == '0);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_q <= '0;
      replace_q <= '0;
    end else begin
      if (flush_valid_i) begin
        for (flush_index = 0; flush_index < ENTRIES_P; flush_index = flush_index + 1) begin
          if (valid_q[flush_index] &&
              (flush_vaddr_all ||
               vpn_matches(flush_vaddr_i[38:12], vpn_q[flush_index], level_q[flush_index])) &&
              (flush_asid_all ||
               (!pte_q[flush_index][5] && (asid_q[flush_index] == flush_asid_i))))
            valid_q[flush_index] <= 1'b0;
        end
        if (flush_vaddr_all && flush_asid_all)
          replace_q <= '0;
      end else if (refill_valid_i) begin
        valid_q[replace_q] <= 1'b1;
        vpn_q[replace_q] <= refill_vaddr_i[38:12];
        asid_q[replace_q] <= refill_asid_i;
        pte_q[replace_q] <= refill_pte_i;
        level_q[replace_q] <= refill_level_i;
        if (replace_q == ENTRY_W'(ENTRIES_P - 1))
          replace_q <= '0;
        else
          replace_q <= replace_q + 1'b1;
      end
    end
  end
endmodule
