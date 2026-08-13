// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

import riscv_pkg::*;

// Combinational EX-stage trap qualification and cause/value selection.
// M1 extends the common M0 trap boundary with U-mode privilege checks and
// mstatus.TW handling for WFI.
module trap_control (
  // Current EX packet and acceptance gate
  input  var id_ex_t  id_ex_i,
  input  logic        ex_accept_i,
  input  logic        ex_side_effects_en_i,

  // Privilege, Debug, and CSR execution context
  input  logic        debug_mode_i,
  input  privilege_mode_e privilege_mode_i,
  input  logic        mstatus_tw_i,
  input  logic        csr_illegal_access_i,
  input  logic        dcsr_ebreakm_i,

  // Resolved EX data result
  input  xlen_t       alu_result_i,

  // Instruction-side access fault and interrupt arbitration
  input  logic        instruction_access_fault_i,
  input  logic        interrupt_ready_i,
  input  xlen_t       interrupt_cause_i,

  // Debug and architectural-return outcomes
  output logic        ebreak_debug_entry_o,
  output logic        mret_trap_o,
  output logic        dret_return_o,

  // Trap classification and WFI legality
  output logic        sync_exception_trap_o,
  output logic        interrupt_trap_o,
  output logic        exception_trap_o,
  output logic        wfi_legal_o,
  output xlen_t       trap_cause_o,
  output xlen_t       trap_value_o
);

  // Raw synchronous exception qualifiers
  logic ecall_trap;
  logic ebreak_trap;
  logic ebreak_regular_trap;
  logic illegal_return_trap;
  logic illegal_csr_trap;
  logic illegal_instr_trap;
  logic wfi_illegal_trap;
  logic load_addr_misaligned;
  logic store_addr_misaligned;

  // ---------------------------------------------------------------------------
  // Raw synchronous exception qualifications
  // ---------------------------------------------------------------------------
  assign ecall_trap = ex_accept_i && (id_ex_i.sys_op == SYS_ECALL);
  assign ebreak_trap = ex_accept_i && (id_ex_i.sys_op == SYS_EBREAK);
  assign ebreak_debug_entry_o = ebreak_trap && dcsr_ebreakm_i && (privilege_mode_i == PRIV_M);
  assign ebreak_regular_trap  = ebreak_trap && (!dcsr_ebreakm_i || (privilege_mode_i != PRIV_M));
  assign illegal_return_trap  = ex_accept_i &&
                                (((id_ex_i.sys_op == SYS_MRET) &&
                                 (debug_mode_i || (privilege_mode_i != PRIV_M))) ||
                                ((id_ex_i.sys_op == SYS_DRET) && !debug_mode_i));
  assign mret_trap_o = ex_accept_i && (id_ex_i.sys_op == SYS_MRET) &&
                       !debug_mode_i && (privilege_mode_i == PRIV_M);
  assign dret_return_o = ex_accept_i && (id_ex_i.sys_op == SYS_DRET) && debug_mode_i;
  // Keep the existing M1 qualification: decoder illegal state is meaningful
  // whenever EX side effects are enabled, even when no valid packet is present.
  assign illegal_instr_trap   = id_ex_i.illegal_instr && ex_side_effects_en_i;
  assign illegal_csr_trap     = ex_accept_i && csr_illegal_access_i;

  // M1-only U-mode restriction. M0 is M-mode-only and therefore has no
  // mstatus.TW-dependent WFI exception.
  // Privileged spec: mstatus.TW restricts WFI only in U-mode. M-mode WFI
  // remains legal, so the core may enter its architectural sleep state.
  assign wfi_illegal_trap = ex_accept_i && (id_ex_i.sys_op == SYS_WFI) &&
                            (privilege_mode_i == PRIV_U) && mstatus_tw_i;
  assign wfi_legal_o = !wfi_illegal_trap;

  // Load/store alignment depends on the access width encoded in mem_type.
  always_comb begin
    load_addr_misaligned = 1'b0;
    store_addr_misaligned = 1'b0;
    unique case (id_ex_i.mem_type)
      3'b001,
      3'b101: begin
        load_addr_misaligned = ex_accept_i && id_ex_i.mem_load && alu_result_i[0];
        store_addr_misaligned = ex_accept_i && id_ex_i.mem_store && alu_result_i[0];
      end
      3'b010: begin
        load_addr_misaligned = ex_accept_i && id_ex_i.mem_load && (alu_result_i[1:0] != 2'b00);
        store_addr_misaligned = ex_accept_i && id_ex_i.mem_store && (alu_result_i[1:0] != 2'b00);
      end
      default: begin
      end
    endcase
  end

  // ---------------------------------------------------------------------------
  // Trap class arbitration
  // A synchronous exception wins over an interrupt for the same EX packet.
  // ---------------------------------------------------------------------------
  assign sync_exception_trap_o = illegal_instr_trap |
                                 illegal_csr_trap |
                                 illegal_return_trap |
                                 instruction_access_fault_i |
                                 wfi_illegal_trap |
                                 ecall_trap |
                                 ebreak_regular_trap |
                                 load_addr_misaligned |
                                 store_addr_misaligned;
  assign interrupt_trap_o = ex_accept_i && !debug_mode_i && interrupt_ready_i &&
                            !sync_exception_trap_o;
  assign exception_trap_o = sync_exception_trap_o | interrupt_trap_o;

  // ---------------------------------------------------------------------------
  // Architectural cause and value selection
  // Keep this order aligned with the raw qualifiers above.
  // ---------------------------------------------------------------------------
  always_comb begin
    if (interrupt_trap_o) begin
      trap_cause_o = interrupt_cause_i;
      trap_value_o = '0;
    end else if (instruction_access_fault_i) begin
      trap_cause_o = xlen_t'(1);
      trap_value_o = id_ex_i.pc;
    end else if (illegal_instr_trap || illegal_csr_trap || illegal_return_trap || wfi_illegal_trap) begin
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
      trap_cause_o = (privilege_mode_i == PRIV_U) ? xlen_t'(8) : xlen_t'(11);
      trap_value_o = '0;
    end
  end

endmodule
