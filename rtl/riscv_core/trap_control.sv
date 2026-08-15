// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

import riscv_pkg::*;

// Combinational EX-stage trap qualification and cause/value selection.
// This block classifies architectural events; CSR state owns delegation,
// trap-vector state, and the M/S/U privilege transition at WB commit.
module trap_control (
  input  var id_ex_t  id_ex_i,
  input  logic        ex_accept_i,
  input  logic        ex_side_effects_en_i,

  input  logic        debug_mode_i,
  input  privilege_mode_e privilege_mode_i,
  input  logic        mstatus_tw_i,
  input  logic        mstatus_tsr_i,
  input  logic        mstatus_tvm_i,
  input  xlen_t       medeleg_i,
  input  logic        csr_illegal_access_i,
  input  logic        dcsr_ebreakm_i,

  input  xlen_t       alu_result_i,

  input  logic        instruction_page_fault_i,
  input  logic        instruction_access_fault_i,
  input  logic        interrupt_ready_i,
  input  logic        interrupt_to_s_i,
  input  xlen_t       interrupt_cause_i,

  output logic        ebreak_debug_entry_o,
  output logic        mret_trap_o,
  output logic        sret_return_o,
  output logic        dret_return_o,

  output logic        sync_exception_trap_o,
  output logic        interrupt_trap_o,
  output logic        exception_trap_o,
  output logic        trap_to_s_o,
  output logic        wfi_legal_o,
  output xlen_t       trap_cause_o,
  output xlen_t       trap_value_o
);

  logic ecall_trap;
  logic ebreak_trap;
  logic ebreak_regular_trap;
  logic illegal_return_trap;
  logic illegal_csr_trap;
  logic illegal_instr_trap;
  logic wfi_illegal_trap;
  logic sfence_vma_illegal_trap;
  logic load_addr_misaligned;
  logic store_addr_misaligned;
  logic atomic_load;
  logic atomic_store;
  logic instruction_page_fault;
  logic instruction_access_fault;

  assign ecall_trap = ex_accept_i && (id_ex_i.sys_op == SYS_ECALL);
  assign ebreak_trap = ex_accept_i && (id_ex_i.sys_op == SYS_EBREAK);
  assign ebreak_debug_entry_o = ebreak_trap && dcsr_ebreakm_i &&
                                (privilege_mode_i == PRIV_M);
  assign ebreak_regular_trap = ebreak_trap &&
                               (!dcsr_ebreakm_i || (privilege_mode_i != PRIV_M));

  assign illegal_return_trap = ex_accept_i &&
      (((id_ex_i.sys_op == SYS_MRET) &&
        (debug_mode_i || (privilege_mode_i != PRIV_M))) ||
       ((id_ex_i.sys_op == SYS_SRET) &&
        (debug_mode_i || (privilege_mode_i != PRIV_S) || mstatus_tsr_i)) ||
       ((id_ex_i.sys_op == SYS_DRET) && !debug_mode_i));
  assign mret_trap_o = ex_accept_i && (id_ex_i.sys_op == SYS_MRET) &&
                       !debug_mode_i && (privilege_mode_i == PRIV_M);
  assign sret_return_o = ex_accept_i && (id_ex_i.sys_op == SYS_SRET) &&
                         !debug_mode_i && (privilege_mode_i == PRIV_S) &&
                         !mstatus_tsr_i;
  assign dret_return_o = ex_accept_i && (id_ex_i.sys_op == SYS_DRET) && debug_mode_i;

  assign illegal_instr_trap = id_ex_i.illegal_instr && ex_side_effects_en_i;
  assign illegal_csr_trap = ex_accept_i && csr_illegal_access_i;
  assign wfi_illegal_trap = ex_accept_i && (id_ex_i.sys_op == SYS_WFI) &&
                            (privilege_mode_i != PRIV_M) && mstatus_tw_i;
  assign sfence_vma_illegal_trap = ex_accept_i &&
                                   (id_ex_i.sys_op == SYS_SFENCE_VMA) &&
                                   (debug_mode_i || (privilege_mode_i == PRIV_U) ||
                                    ((privilege_mode_i == PRIV_S) && mstatus_tvm_i));
  assign wfi_legal_o = !wfi_illegal_trap;
  assign atomic_load = id_ex_i.atomic_op == ATOMIC_LR;
  assign atomic_store = (id_ex_i.atomic_op != ATOMIC_NONE) &&
                        (id_ex_i.atomic_op != ATOMIC_LR);
  assign instruction_page_fault = ex_accept_i && instruction_page_fault_i;
  assign instruction_access_fault = ex_accept_i && instruction_access_fault_i;

  always_comb begin
    load_addr_misaligned = 1'b0;
    store_addr_misaligned = 1'b0;
    unique case (id_ex_i.mem_type)
      3'b001,
      3'b101: begin
        load_addr_misaligned = ex_accept_i &&
                               ((id_ex_i.mem_load && (id_ex_i.atomic_op == ATOMIC_NONE)) ||
                                atomic_load) && alu_result_i[0];
        store_addr_misaligned = ex_accept_i &&
                                (id_ex_i.mem_store || atomic_store) && alu_result_i[0];
      end
      3'b010: begin
        load_addr_misaligned = ex_accept_i &&
                               ((id_ex_i.mem_load && (id_ex_i.atomic_op == ATOMIC_NONE)) ||
                                atomic_load) && (alu_result_i[1:0] != 2'b00);
        store_addr_misaligned = ex_accept_i &&
                                (id_ex_i.mem_store || atomic_store) &&
                                (alu_result_i[1:0] != 2'b00);
      end
      3'b011: begin
        load_addr_misaligned = ex_accept_i &&
                               ((id_ex_i.mem_load && (id_ex_i.atomic_op == ATOMIC_NONE)) ||
                                atomic_load) && (alu_result_i[2:0] != 3'b000);
        store_addr_misaligned = ex_accept_i &&
                                (id_ex_i.mem_store || atomic_store) &&
                                (alu_result_i[2:0] != 3'b000);
      end
      default: begin
      end
    endcase
  end

  assign sync_exception_trap_o = illegal_instr_trap |
                                 illegal_csr_trap |
                                 illegal_return_trap |
                                 instruction_page_fault |
                                 instruction_access_fault |
                                 wfi_illegal_trap |
                                 sfence_vma_illegal_trap |
                                 ecall_trap |
                                 ebreak_regular_trap |
                                 load_addr_misaligned |
                                 store_addr_misaligned;
  assign interrupt_trap_o = ex_accept_i && !debug_mode_i && interrupt_ready_i &&
                            !sync_exception_trap_o;
  assign exception_trap_o = sync_exception_trap_o | interrupt_trap_o;

  always_comb begin
    if (interrupt_trap_o) begin
      trap_cause_o = interrupt_cause_i;
      trap_value_o = '0;
    end else if (instruction_page_fault) begin
      trap_cause_o = xlen_t'(12);
      trap_value_o = id_ex_i.pc;
    end else if (instruction_access_fault) begin
      trap_cause_o = xlen_t'(1);
      trap_value_o = id_ex_i.pc;
    end else if (illegal_instr_trap || illegal_csr_trap || illegal_return_trap ||
                 wfi_illegal_trap || sfence_vma_illegal_trap) begin
      trap_cause_o = xlen_t'(2);
      trap_value_o = xlen_t'(id_ex_i.instr);
    end else if (load_addr_misaligned) begin
      trap_cause_o = xlen_t'(4);
      trap_value_o = alu_result_i;
    end else if (store_addr_misaligned) begin
      trap_cause_o = xlen_t'(6);
      trap_value_o = alu_result_i;
    end else if (ebreak_trap) begin
      trap_cause_o = xlen_t'(3);
      trap_value_o = '0;
    end else begin
      unique case (privilege_mode_i)
        PRIV_U:  trap_cause_o = xlen_t'(8);
        PRIV_S:  trap_cause_o = xlen_t'(9);
        default: trap_cause_o = xlen_t'(11);
      endcase
      trap_value_o = '0;
    end
  end

  assign trap_to_s_o = (sync_exception_trap_o && (privilege_mode_i != PRIV_M) &&
                        medeleg_i[trap_cause_o[5:0]]) ||
                       (interrupt_trap_o && interrupt_to_s_i);

endmodule
