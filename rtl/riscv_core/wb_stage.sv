// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

import riscv_pkg::*;

// Writeback stage adapter. It turns the MEM/WB bundle into the architectural
// retire pulse and register-file write interface.
module wb_stage (
  // MEM/WB pipeline packet
  input  var mem_wb_t mem_wb_i,

  // Architectural GPR writeback
  output logic [4:0]  rd_addr_o,
  output xlen_t       rd_data_o,
  output logic        rd_we_o,

  // FPR writeback and FCSR retirement
  output logic        fp_we_o,
  output logic [4:0]  fp_rd_addr_o,
  output logic [63:0] fp_rd_data_o,
  output logic [4:0]  fp_fflags_o,
  output logic        fp_dirty_o,

  // Committed control class. Decode the packet at its ownership boundary so
  // the core consumes named events rather than re-decoding pipeline metadata.
  output logic        control_commit_o,
  output logic        control_trap_enter_o,
  output logic        control_trap_return_o,
  output logic        control_sret_return_o,
  output logic        control_debug_enter_o,
  output logic        control_debug_return_o,
  output logic        control_wfi_o,
  output logic        control_sfence_vma_o,
  output xlen_t       control_sfence_vma_vaddr_o,
  output logic [15:0] control_sfence_vma_asid_o,
  output xlen_t       control_trap_pc_o,
  output xlen_t       control_trap_cause_o,
  output xlen_t       control_trap_value_o,
  output xlen_t       control_debug_dpc_o,
  output logic [2:0]  control_debug_cause_o
);

  // x0 suppression applies only to the physical register-file write.
  assign rd_addr_o      = mem_wb_i.rd_addr;
  assign rd_data_o      = mem_wb_i.wb_data;
  assign rd_we_o        = mem_wb_i.valid & mem_wb_i.rd_we & (mem_wb_i.rd_addr != 5'd0);
  assign fp_we_o        = mem_wb_i.valid & mem_wb_i.fp_write;
  assign fp_rd_addr_o   = mem_wb_i.fp_rd_addr;
  assign fp_rd_data_o   = mem_wb_i.fp_dst_fmt == FP_FMT_D ? mem_wb_i.wb_data :
                          {32'hffff_ffff, mem_wb_i.wb_data[31:0]};
  assign fp_fflags_o    = mem_wb_i.fp_fflags;
  assign fp_dirty_o     = mem_wb_i.valid & mem_wb_i.fp_dirty;
  assign control_commit_o       = mem_wb_i.valid & (mem_wb_i.control_source != CONTROL_NONE);
  assign control_trap_enter_o   = mem_wb_i.valid &&
                                  (mem_wb_i.control_source == CONTROL_EXCEPTION);
  assign control_trap_return_o  = mem_wb_i.valid &&
                                  (mem_wb_i.control_source == CONTROL_MRET);
  assign control_sret_return_o  = mem_wb_i.valid &&
                                  (mem_wb_i.control_source == CONTROL_SRET);
  assign control_debug_enter_o  = mem_wb_i.valid &&
                                  ((mem_wb_i.control_source == CONTROL_DEBUG_ENTER) ||
                                   (mem_wb_i.control_source == CONTROL_DEBUG_STEP));
  assign control_debug_return_o = mem_wb_i.valid &&
                                  (mem_wb_i.control_source == CONTROL_DRET);
  assign control_wfi_o          = mem_wb_i.valid &&
                                  (mem_wb_i.control_source == CONTROL_WFI);
  assign control_sfence_vma_o   = mem_wb_i.valid &&
                                  (mem_wb_i.control_source == CONTROL_SFENCE_VMA);
  assign control_sfence_vma_vaddr_o = mem_wb_i.control_sfence_vma_vaddr;
  assign control_sfence_vma_asid_o = mem_wb_i.control_sfence_vma_asid;
  assign control_trap_pc_o      = mem_wb_i.control_trap_pc;
  assign control_trap_cause_o   = mem_wb_i.control_trap_cause;
  assign control_trap_value_o   = mem_wb_i.control_trap_value;
  assign control_debug_dpc_o    = mem_wb_i.control_debug_dpc;
  assign control_debug_cause_o  = mem_wb_i.control_debug_cause;

endmodule
