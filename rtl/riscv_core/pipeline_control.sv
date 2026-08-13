// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

import riscv_pkg::*;

// Central pipeline enable/flush controller for the RV64GC baseline.
module pipeline_control (
  input  logic        fetch_enable_i,
  input  logic        imem_wait_i,
  input  logic        dmem_wait_i,
  input  logic        load_use_stall_i,
  input  logic        muldiv_wait_i,
  input  logic        fpu_wait_i,
  input  logic        control_event_i,
  input  logic        trap_redirect_i,
  input  xlen_t       trap_redirect_pc_i,
  input  logic        debug_redirect_i,
  input  xlen_t       debug_redirect_pc_i,
  input  logic        fence_i_redirect_i,
  input  xlen_t       fence_i_redirect_pc_i,
  input  logic        wfi_redirect_i,
  input  xlen_t       wfi_redirect_pc_i,
  input  logic        branch_redirect_i,
  input  xlen_t       branch_redirect_pc_i,
  output logic        pc_en_o,
  output logic        if_id_en_o,
  output logic        backend_advance_o,
  output logic        if_id_flush_o,
  output logic        id_ex_flush_o,
  output logic        ex_mem_flush_o,
  output logic        redirect_valid_o,
  output xlen_t       redirect_pc_o
);
  logic front_stall;
  logic full_stall;

  assign redirect_valid_o = trap_redirect_i | debug_redirect_i |
                            fence_i_redirect_i | wfi_redirect_i |
                            branch_redirect_i;
  always_comb begin
    redirect_pc_o = branch_redirect_pc_i;
    if (wfi_redirect_i) redirect_pc_o = wfi_redirect_pc_i;
    if (fence_i_redirect_i) redirect_pc_o = fence_i_redirect_pc_i;
    if (debug_redirect_i) redirect_pc_o = debug_redirect_pc_i;
    if (trap_redirect_i) redirect_pc_o = trap_redirect_pc_i;
  end

  assign front_stall = imem_wait_i | load_use_stall_i;
  assign full_stall = dmem_wait_i | muldiv_wait_i | fpu_wait_i;
  assign pc_en_o = fetch_enable_i & ~front_stall & ~full_stall;
  assign if_id_en_o = ~front_stall & ~full_stall;
  assign backend_advance_o = ~full_stall;
  assign if_id_flush_o = redirect_valid_o;
  assign id_ex_flush_o = redirect_valid_o | (load_use_stall_i & ~full_stall);
  assign ex_mem_flush_o = trap_redirect_i & ~control_event_i;
endmodule
