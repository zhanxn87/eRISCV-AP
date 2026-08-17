// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

import riscv_pkg::*;
import sv39_pkg::*;

// One-request shared Sv39 page-table walker. PTE accesses are physical 64-bit
// transactions supplied by the hart-local D-Cache/PTW port. Leaf A/D bits are
// set with an atomic OR before the translation is returned or cached.
module sv39_ptw (
  input  logic            clk,
  input  logic            rst_n,

  // Translation miss request. The requester must hold fields stable until
  // req_ready_o accepts the transaction.
  input  logic            req_valid_i,
  output logic            req_ready_o,
  input  xlen_t           req_vaddr_i,
  input  xlen_t           req_satp_i,
  input  privilege_mode_e req_privilege_i,
  input  sv39_access_e    req_access_i,
  input  logic            req_cbo_i,
  input  logic            req_sum_i,
  input  logic            req_mxr_i,

  // Translation response. resp_fault_o reports a page-table/permission fault;
  // resp_access_fault_o reports a failed physical page-table access.
  output logic            resp_valid_o,
  input  logic            resp_ready_i,
  output paddr_t          resp_paddr_o,
  output logic            resp_fault_o,
  output logic            resp_access_fault_o,
  output xlen_t           resp_pte_o,
  output logic [1:0]      resp_level_o,

  // Dedicated physical PTE port. This interface does not recurse through the
  // DTLB and uses AMOOR for hardware A/D updates.
  output logic            pte_req_valid_o,
  input  logic            pte_req_ready_i,
  output paddr_t          pte_req_addr_o,
  output xlen_t           pte_req_wdata_o,
  output atomic_op_e      pte_req_atomic_op_o,
  input  logic            pte_resp_valid_i,
  input  xlen_t           pte_resp_rdata_i,
  input  logic            pte_resp_err_i
);
  typedef enum logic [2:0] {
    PTW_IDLE,
    PTW_PTE_REQ,
    PTW_PTE_WAIT,
    PTW_AD_UPDATE_REQ,
    PTW_AD_UPDATE_WAIT,
    PTW_RESP
  } ptw_state_e;

  ptw_state_e state_q;
  xlen_t req_vaddr_q;
  privilege_mode_e req_privilege_q;
  sv39_access_e req_access_q;
  logic req_cbo_q;
  logic req_sum_q;
  logic req_mxr_q;
  logic [43:0] current_ppn_q;
  logic [1:0] level_q;
  paddr_t pte_addr;
  logic [8:0] pte_index;

  logic canonical;
  logic pte_valid;
  logic pte_leaf;
  logic ppn_in_range;
  logic superpage_aligned;
  logic permission_ok;
  xlen_t pte_ad_update_mask;
  logic pte_fault;
  paddr_t checked_paddr;
  xlen_t ad_update_mask_q;

  logic resp_fault_q;
  logic resp_access_fault_q;
  paddr_t resp_paddr_q;
  xlen_t resp_pte_q;
  logic [1:0] resp_level_q;
  satp_sv39_t req_satp;

  assign req_satp = decode_satp(req_satp_i);
  assign req_ready_o = (state_q == PTW_IDLE);
  assign resp_valid_o = (state_q == PTW_RESP);
  assign resp_fault_o = resp_fault_q;
  assign resp_access_fault_o = resp_access_fault_q;
  assign resp_paddr_o = resp_paddr_q;
  assign resp_pte_o = resp_pte_q;
  assign resp_level_o = resp_level_q;
  assign pte_req_valid_o = (state_q == PTW_PTE_REQ) ||
                           (state_q == PTW_AD_UPDATE_REQ);
  assign pte_req_wdata_o = (state_q == PTW_AD_UPDATE_REQ) ? ad_update_mask_q : '0;
  assign pte_req_atomic_op_o = (state_q == PTW_AD_UPDATE_REQ) ? ATOMIC_OR : ATOMIC_NONE;

  always_comb begin
    unique case (level_q)
      2'd2: pte_index = req_vaddr_q[38:30];
      2'd1: pte_index = req_vaddr_q[29:21];
      default: pte_index = req_vaddr_q[20:12];
    endcase
    pte_addr = {current_ppn_q[35:0], 12'b0} +
               (paddr_t'(pte_index) << 3);
  end
  assign pte_req_addr_o = pte_addr;

  sv39_pte_check pte_check_i (
    .vaddr_i(req_vaddr_q),
    .pte_i(pte_resp_rdata_i),
    .level_i(level_q),
    .privilege_i(req_privilege_q),
    .access_i(req_access_q),
    .cbo_i(req_cbo_q),
    .sum_i(req_sum_q),
    .mxr_i(req_mxr_q),
    .canonical_o(canonical),
    .pte_valid_o(pte_valid),
    .pte_leaf_o(pte_leaf),
    .ppn_in_range_o(ppn_in_range),
    .superpage_aligned_o(superpage_aligned),
    .permission_ok_o(permission_ok),
    .ad_update_mask_o(pte_ad_update_mask),
    .fault_o(pte_fault),
    .paddr_o(checked_paddr)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= PTW_IDLE;
      req_vaddr_q <= '0;
      req_privilege_q <= PRIV_M;
      req_access_q <= SV39_ACCESS_FETCH;
      req_cbo_q <= 1'b0;
      req_sum_q <= 1'b0;
      req_mxr_q <= 1'b0;
      current_ppn_q <= '0;
      level_q <= 2'd2;
      resp_fault_q <= 1'b0;
      resp_access_fault_q <= 1'b0;
      resp_paddr_q <= '0;
      resp_pte_q <= '0;
      resp_level_q <= '0;
      ad_update_mask_q <= '0;
    end else begin
      unique case (state_q)
        PTW_IDLE: begin
          if (req_valid_i) begin
            req_vaddr_q <= req_vaddr_i;
            req_privilege_q <= req_privilege_i;
            req_access_q <= req_access_i;
            req_cbo_q <= req_cbo_i;
            req_sum_q <= req_sum_i;
            req_mxr_q <= req_mxr_i;
            current_ppn_q <= req_satp.ppn;
            level_q <= 2'd2;
            resp_fault_q <= !sv39_canonical(req_vaddr_i) ||
                            (req_satp.mode != SV39_MODE_SV39) ||
                            (req_satp.ppn[43:36] != '0);
            resp_access_fault_q <= 1'b0;
            resp_paddr_q <= '0;
            resp_pte_q <= '0;
            resp_level_q <= 2'd2;
            state_q <= (!sv39_canonical(req_vaddr_i) ||
                        (req_satp.mode != SV39_MODE_SV39) ||
                        (req_satp.ppn[43:36] != '0)) ? PTW_RESP : PTW_PTE_REQ;
          end
        end

        PTW_PTE_REQ: begin
          if (pte_req_ready_i)
            state_q <= PTW_PTE_WAIT;
        end

        PTW_PTE_WAIT: begin
          if (pte_resp_valid_i) begin
            resp_pte_q <= pte_resp_rdata_i;
            resp_level_q <= level_q;
            if (pte_resp_err_i) begin
              resp_fault_q <= 1'b0;
              resp_access_fault_q <= 1'b1;
              resp_paddr_q <= '0;
              state_q <= PTW_RESP;
            end else if (!pte_valid || !canonical || !ppn_in_range ||
                         (pte_leaf && pte_fault) || (!pte_leaf && (level_q == 2'd0))) begin
              resp_fault_q <= 1'b1;
              resp_access_fault_q <= 1'b0;
              resp_paddr_q <= '0;
              state_q <= PTW_RESP;
            end else if (pte_leaf && (pte_ad_update_mask != '0)) begin
              ad_update_mask_q <= pte_ad_update_mask;
              state_q <= PTW_AD_UPDATE_REQ;
            end else if (pte_leaf) begin
              resp_fault_q <= 1'b0;
              resp_access_fault_q <= 1'b0;
              resp_paddr_q <= checked_paddr;
              state_q <= PTW_RESP;
            end else begin
              current_ppn_q <= pte_resp_rdata_i[53:10];
              level_q <= level_q - 2'd1;
              state_q <= PTW_PTE_REQ;
            end
          end
        end

        PTW_AD_UPDATE_REQ: begin
          if (pte_req_ready_i)
            state_q <= PTW_AD_UPDATE_WAIT;
        end

        PTW_AD_UPDATE_WAIT: begin
          if (pte_resp_valid_i) begin
            resp_pte_q <= pte_resp_rdata_i | ad_update_mask_q;
            resp_level_q <= level_q;
            if (pte_resp_err_i) begin
              resp_fault_q <= 1'b0;
              resp_access_fault_q <= 1'b1;
              resp_paddr_q <= '0;
            end else begin
              resp_fault_q <= 1'b0;
              resp_access_fault_q <= 1'b0;
              resp_paddr_q <= checked_paddr;
            end
            state_q <= PTW_RESP;
          end
        end

        PTW_RESP: begin
          if (resp_ready_i)
            state_q <= PTW_IDLE;
        end

        default: state_q <= PTW_IDLE;
      endcase
    end
  end
endmodule
