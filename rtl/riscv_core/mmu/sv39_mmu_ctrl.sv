// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

import riscv_pkg::*;
import sv39_pkg::*;

// Hart-local Sv39 translation controller. ITLB and DTLB lookups proceed
// independently; their misses share one physical PTE-read port through the
// PTW. The caller supplies the effective privilege, so MPRV policy remains in
// the CSR/core boundary rather than being duplicated here.
module sv39_mmu_ctrl #(
  parameter int unsigned TLB_ENTRIES_P = 16
) (
  input  logic            clk,
  input  logic            rst_n,

  // SFENCE.VMA invalidation selector. The caller serializes the event before
  // asserting it; a zero VA or ASID carries the architectural all selector.
  input  logic            flush_valid_i,
  input  xlen_t           flush_vaddr_i,
  input  logic [15:0]     flush_asid_i,

  // Instruction-side virtual request and translation response.
  input  logic            i_req_valid_i,
  output logic            i_req_ready_o,
  input  xlen_t           i_req_vaddr_i,
  input  xlen_t           i_req_satp_i,
  input  privilege_mode_e i_req_privilege_i,
  input  logic            i_req_sum_i,
  input  logic            i_req_mxr_i,
  output logic            i_resp_valid_o,
  input  logic            i_resp_ready_i,
  output paddr_t          i_resp_paddr_o,
  output logic            i_resp_page_fault_o,
  output logic            i_resp_access_fault_o,

  // Data-side virtual request and translation response.
  input  logic            d_req_valid_i,
  output logic            d_req_ready_o,
  input  xlen_t           d_req_vaddr_i,
  input  xlen_t           d_req_satp_i,
  input  privilege_mode_e d_req_privilege_i,
  input  sv39_access_e    d_req_access_i,
  input  logic            d_req_sum_i,
  input  logic            d_req_mxr_i,
  output logic            d_resp_valid_o,
  input  logic            d_resp_ready_i,
  output paddr_t          d_resp_paddr_o,
  output logic            d_resp_page_fault_o,
  output logic            d_resp_access_fault_o,

  // Dedicated physical PTE port. It connects to the D-cache/PTW port, never
  // to the virtual data request path, and carries AMOOR A/D updates.
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
    MMU_IDLE,
    MMU_LOOKUP,
    MMU_PTW_REQ,
    MMU_PTW_WAIT,
    MMU_REFILL,
    MMU_RESP
  } mmu_state_e;

  mmu_state_e state_q;
  logic active_i_q;
  xlen_t active_vaddr_q;
  xlen_t active_satp_q;
  privilege_mode_e active_privilege_q;
  sv39_access_e active_access_q;
  logic active_sum_q;
  logic active_mxr_q;
  satp_sv39_t active_satp;
  logic bypass_translation;

  paddr_t resp_paddr_q;
  logic resp_page_fault_q;
  logic resp_access_fault_q;
  xlen_t ptw_pte_q;
  logic [1:0] ptw_level_q;

  logic itlb_hit;
  logic itlb_fault;
  xlen_t itlb_ad_update_mask;
  paddr_t itlb_paddr;
  logic dtlb_hit;
  logic dtlb_fault;
  xlen_t dtlb_ad_update_mask;
  paddr_t dtlb_paddr;
  logic selected_tlb_hit;
  logic selected_tlb_fault;
  xlen_t selected_tlb_ad_update_mask;
  paddr_t selected_tlb_paddr;

  logic ptw_req_valid;
  logic ptw_req_ready;
  logic ptw_resp_valid;
  logic ptw_resp_fault;
  logic ptw_resp_access_fault;
  paddr_t ptw_resp_paddr;
  xlen_t ptw_resp_pte;
  logic [1:0] ptw_resp_level;

  assign active_satp = decode_satp(active_satp_q);
  assign bypass_translation = (active_privilege_q == PRIV_M) ||
                              (active_satp.mode == SV39_MODE_BARE);

  sv39_tlb #(.ENTRIES_P(TLB_ENTRIES_P)) itlb_i (
    .clk,
    .rst_n,
    .lookup_valid_i((state_q == MMU_LOOKUP) && active_i_q && !bypass_translation),
    .lookup_vaddr_i(active_vaddr_q),
    .lookup_asid_i(active_satp.asid),
    .lookup_privilege_i(active_privilege_q),
    .lookup_access_i(SV39_ACCESS_FETCH),
    .lookup_sum_i(active_sum_q),
    .lookup_mxr_i(active_mxr_q),
    .lookup_hit_o(itlb_hit),
    .lookup_fault_o(itlb_fault),
    .lookup_ad_update_mask_o(itlb_ad_update_mask),
    .lookup_paddr_o(itlb_paddr),
    .refill_valid_i((state_q == MMU_REFILL) && active_i_q),
    .refill_vaddr_i(active_vaddr_q),
    .refill_asid_i(active_satp.asid),
    .refill_pte_i(ptw_pte_q),
    .refill_level_i(ptw_level_q),
    .flush_valid_i(flush_valid_i),
    .flush_vaddr_i(flush_vaddr_i),
    .flush_asid_i(flush_asid_i)
  );

  sv39_tlb #(.ENTRIES_P(TLB_ENTRIES_P)) dtlb_i (
    .clk,
    .rst_n,
    .lookup_valid_i((state_q == MMU_LOOKUP) && !active_i_q && !bypass_translation),
    .lookup_vaddr_i(active_vaddr_q),
    .lookup_asid_i(active_satp.asid),
    .lookup_privilege_i(active_privilege_q),
    .lookup_access_i(active_access_q),
    .lookup_sum_i(active_sum_q),
    .lookup_mxr_i(active_mxr_q),
    .lookup_hit_o(dtlb_hit),
    .lookup_fault_o(dtlb_fault),
    .lookup_ad_update_mask_o(dtlb_ad_update_mask),
    .lookup_paddr_o(dtlb_paddr),
    .refill_valid_i((state_q == MMU_REFILL) && !active_i_q),
    .refill_vaddr_i(active_vaddr_q),
    .refill_asid_i(active_satp.asid),
    .refill_pte_i(ptw_pte_q),
    .refill_level_i(ptw_level_q),
    .flush_valid_i(flush_valid_i),
    .flush_vaddr_i(flush_vaddr_i),
    .flush_asid_i(flush_asid_i)
  );

  always_comb begin
    if (active_i_q) begin
      selected_tlb_hit = itlb_hit;
      selected_tlb_fault = itlb_fault;
      selected_tlb_ad_update_mask = itlb_ad_update_mask;
      selected_tlb_paddr = itlb_paddr;
    end else begin
      selected_tlb_hit = dtlb_hit;
      selected_tlb_fault = dtlb_fault;
      selected_tlb_ad_update_mask = dtlb_ad_update_mask;
      selected_tlb_paddr = dtlb_paddr;
    end
  end

  sv39_ptw ptw_i (
    .clk,
    .rst_n,
    .req_valid_i(ptw_req_valid),
    .req_ready_o(ptw_req_ready),
    .req_vaddr_i(active_vaddr_q),
    .req_satp_i(active_satp_q),
    .req_privilege_i(active_privilege_q),
    .req_access_i(active_access_q),
    .req_sum_i(active_sum_q),
    .req_mxr_i(active_mxr_q),
    .resp_valid_o(ptw_resp_valid),
    .resp_ready_i(state_q == MMU_PTW_WAIT),
    .resp_paddr_o(ptw_resp_paddr),
    .resp_fault_o(ptw_resp_fault),
    .resp_access_fault_o(ptw_resp_access_fault),
    .resp_pte_o(ptw_resp_pte),
    .resp_level_o(ptw_resp_level),
    .pte_req_valid_o(pte_req_valid_o),
    .pte_req_ready_i(pte_req_ready_i),
    .pte_req_addr_o(pte_req_addr_o),
    .pte_req_wdata_o(pte_req_wdata_o),
    .pte_req_atomic_op_o(pte_req_atomic_op_o),
    .pte_resp_valid_i(pte_resp_valid_i),
    .pte_resp_rdata_i(pte_resp_rdata_i),
    .pte_resp_err_i(pte_resp_err_i)
  );

  assign ptw_req_valid = (state_q == MMU_PTW_REQ);

  always_comb begin
    i_req_ready_o = (state_q == MMU_IDLE) && !flush_valid_i;
    d_req_ready_o = (state_q == MMU_IDLE) && !flush_valid_i && !i_req_valid_i;

    i_resp_valid_o = (state_q == MMU_RESP) && active_i_q;
    d_resp_valid_o = (state_q == MMU_RESP) && !active_i_q;
    i_resp_paddr_o = resp_paddr_q;
    d_resp_paddr_o = resp_paddr_q;
    i_resp_page_fault_o = resp_page_fault_q;
    d_resp_page_fault_o = resp_page_fault_q;
    i_resp_access_fault_o = resp_access_fault_q;
    d_resp_access_fault_o = resp_access_fault_q;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= MMU_IDLE;
      active_i_q <= 1'b0;
      active_vaddr_q <= '0;
      active_satp_q <= '0;
      active_privilege_q <= PRIV_M;
      active_access_q <= SV39_ACCESS_FETCH;
      active_sum_q <= 1'b0;
      active_mxr_q <= 1'b0;
      resp_paddr_q <= '0;
      resp_page_fault_q <= 1'b0;
      resp_access_fault_q <= 1'b0;
      ptw_pte_q <= '0;
      ptw_level_q <= '0;
    end else begin
      unique case (state_q)
        MMU_IDLE: begin
          if (!flush_valid_i && i_req_valid_i) begin
            active_i_q <= 1'b1;
            active_vaddr_q <= i_req_vaddr_i;
            active_satp_q <= i_req_satp_i;
            active_privilege_q <= i_req_privilege_i;
            active_access_q <= SV39_ACCESS_FETCH;
            active_sum_q <= i_req_sum_i;
            active_mxr_q <= i_req_mxr_i;
            state_q <= MMU_LOOKUP;
          end else if (!flush_valid_i && d_req_valid_i) begin
            active_i_q <= 1'b0;
            active_vaddr_q <= d_req_vaddr_i;
            active_satp_q <= d_req_satp_i;
            active_privilege_q <= d_req_privilege_i;
            active_access_q <= d_req_access_i;
            active_sum_q <= d_req_sum_i;
            active_mxr_q <= d_req_mxr_i;
            state_q <= MMU_LOOKUP;
          end
        end

        MMU_LOOKUP: begin
          if (bypass_translation) begin
            resp_paddr_q <= active_vaddr_q[47:0];
            resp_page_fault_q <= 1'b0;
            resp_access_fault_q <= |active_vaddr_q[63:48];
            state_q <= MMU_RESP;
          end else if (selected_tlb_hit && selected_tlb_fault) begin
            resp_paddr_q <= selected_tlb_paddr;
            resp_page_fault_q <= 1'b1;
            resp_access_fault_q <= 1'b0;
            state_q <= MMU_RESP;
          end else if (selected_tlb_hit && (selected_tlb_ad_update_mask == '0)) begin
            resp_paddr_q <= selected_tlb_paddr;
            resp_page_fault_q <= 1'b0;
            resp_access_fault_q <= 1'b0;
            state_q <= MMU_RESP;
          end else begin
            state_q <= MMU_PTW_REQ;
          end
        end

        MMU_PTW_REQ: begin
          if (ptw_req_ready)
            state_q <= MMU_PTW_WAIT;
        end

        MMU_PTW_WAIT: begin
          if (ptw_resp_valid) begin
            resp_paddr_q <= ptw_resp_paddr;
            resp_page_fault_q <= ptw_resp_fault;
            resp_access_fault_q <= ptw_resp_access_fault;
            ptw_pte_q <= ptw_resp_pte;
            ptw_level_q <= ptw_resp_level;
            state_q <= (ptw_resp_fault || ptw_resp_access_fault) ? MMU_RESP : MMU_REFILL;
          end
        end

        MMU_REFILL: state_q <= MMU_RESP;

        MMU_RESP: begin
          if ((active_i_q && i_resp_ready_i) ||
              (!active_i_q && d_resp_ready_i))
            state_q <= MMU_IDLE;
        end

        default: state_q <= MMU_IDLE;
      endcase
    end
  end
endmodule
