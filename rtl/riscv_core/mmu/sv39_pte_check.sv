// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

import riscv_pkg::*;
import sv39_pkg::*;

// Combinational Sv39 PTE validation and leaf permission check. The PTW owns
// the non-leaf walk sequencing and A/D update policy; this block makes all
// leaf decisions independent of the cache and AXI implementation.
module sv39_pte_check (
  input  xlen_t            vaddr_i,
  input  xlen_t            pte_i,
  input  logic [1:0]       level_i,
  input  privilege_mode_e  privilege_i,
  input  sv39_access_e     access_i,
  input  logic             sum_i,
  input  logic             mxr_i,
  output logic             canonical_o,
  output logic             pte_valid_o,
  output logic             pte_leaf_o,
  output logic             ppn_in_range_o,
  output logic             superpage_aligned_o,
  output logic             permission_ok_o,
  output xlen_t            ad_update_mask_o,
  output logic             fault_o,
  output paddr_t           paddr_o
);
  logic pte_r;
  logic pte_w;
  logic pte_x;
  logic pte_u;
  logic pte_a;
  logic pte_d;
  logic privilege_ok;
  logic access_ok;
  logic [43:0] pte_ppn;
  logic [43:0] translated_ppn;
  logic [26:0] vpn;

  assign pte_r = pte_i[1];
  assign pte_w = pte_i[2];
  assign pte_x = pte_i[3];
  assign pte_u = pte_i[4];
  assign pte_a = pte_i[6];
  assign pte_d = pte_i[7];
  assign pte_ppn = pte_i[53:10];
  assign vpn = vaddr_i[38:12];

  assign canonical_o = sv39_canonical(vaddr_i);
  assign pte_valid_o = pte_i[0] && !(pte_w && !pte_r);
  assign pte_leaf_o = pte_r || pte_x;
  assign ppn_in_range_o = (pte_ppn[43:36] == '0);

  always_comb begin
    translated_ppn = pte_ppn;
    superpage_aligned_o = 1'b1;
    unique case (level_i)
      2'd2: begin
        translated_ppn = {pte_ppn[43:18], vpn[17:0]};
        superpage_aligned_o = (pte_ppn[17:0] == '0);
      end
      2'd1: begin
        translated_ppn = {pte_ppn[43:9], vpn[8:0]};
        superpage_aligned_o = (pte_ppn[8:0] == '0);
      end
      default: begin
      end
    endcase
  end

  always_comb begin
    unique case (privilege_i)
      PRIV_U: privilege_ok = pte_u;
      PRIV_S: privilege_ok = !pte_u ||
                             ((access_i != SV39_ACCESS_FETCH) && sum_i);
      default: privilege_ok = 1'b1;
    endcase

    unique case (access_i)
      SV39_ACCESS_FETCH: access_ok = pte_x;
      SV39_ACCESS_LOAD:  access_ok = pte_r || (mxr_i && pte_x);
      default:           access_ok = pte_w;
    endcase
    permission_ok_o = privilege_ok && access_ok;
  end

  // Sv39 permits hardware to set A on every leaf access and D on stores.
  // The PTW performs this as an atomic OR after the permission check; keeping
  // the required bit mask separate lets a TLB hit request the same update.
  always_comb begin
    ad_update_mask_o = '0;
    if (pte_leaf_o && pte_valid_o && canonical_o && ppn_in_range_o &&
        superpage_aligned_o && permission_ok_o) begin
      if (!pte_a)
        ad_update_mask_o[6] = 1'b1;
      if ((access_i == SV39_ACCESS_STORE) && !pte_d)
        ad_update_mask_o[7] = 1'b1;
    end
  end

  assign paddr_o = {translated_ppn[35:0], vaddr_i[11:0]};
  assign fault_o = !canonical_o || !pte_valid_o ||
                   (pte_leaf_o && (!ppn_in_range_o || !superpage_aligned_o ||
                                   !permission_ok_o));
endmodule
