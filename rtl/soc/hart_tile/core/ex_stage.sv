// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

import riscv_pkg::*;

// Execute stage datapath and control stage.
// This stage resolves forwarding, ALU/branch results, traps, interrupts, and
// debug-mode entry/return before handing the packet to MEM.
//
// Trap priority (highest to lowest, per RISC-V privileged spec):
//   1. Synchronous exceptions (illegal instr, ECALL, misaligned, etc.)
//   2. Interrupts (only if no sync exception and MIE=1 in mstatus)
//
// On exception_trap the pipeline redirects to mtvec and the CSR file captures
// MEPC/MCAUSE/MTVAL in the same cycle.  MRET restores PC from MEPC.
module ex_stage #(
  parameter xlen_t RESET_VECTOR_ADDR_P = xlen_t'(RESET_VECTOR_ADDR),
  parameter xlen_t DEBUG_BASE_ADDR_P   = xlen_t'(DEBUG_BASE_ADDR),
  parameter int unsigned MUL_ITER_BITS_P = 8
) (
  // Clock and reset
  input  logic        clk,
  input  logic        rst_n,

  // Pipeline packets and EX/MEM boundary
  input  var id_ex_t  id_ex_i,
  input  var ex_mem_t ex_mem_fwd_i,
  input  var mem_wb_t mem_wb_fwd_i,
  input  logic        load_result_bypass_valid_i,
  input  logic [4:0]  load_result_bypass_rd_addr_i,
  input  xlen_t       load_result_bypass_data_i,
  input  logic        ex_mem_en_i,
  input  logic        ex_mem_flush_i,
  output ex_mem_t     ex_mem_o,

  // Platform event inputs
  input  logic [31:0] irq_i,
  input  logic [63:0] mtime_i,

  // Retired control event from WB
  input  logic        control_trap_enter_i,
  input  logic        control_trap_return_i,
  input  logic        control_sret_return_i,
  input  logic        control_debug_enter_i,
  input  xlen_t       control_trap_pc_i,
  input  xlen_t       control_trap_cause_i,
  input  xlen_t       control_trap_value_i,
  input  xlen_t       control_debug_dpc_i,
  input  logic [2:0]  control_debug_cause_i,

  // Older data faults complete in MEM. They suppress this younger EX packet;
  // EX still owns the CSR delegation and trap-vector selection.
  input  logic        mem_fault_valid_i,
  input  xlen_t       mem_fault_cause_i,
  output logic        mem_fault_redirect_o,
  output xlen_t       mem_fault_redirect_pc_o,

  // Debug run control and abstract CSR access
  input  logic        debug_mode_i,
  input  logic        debug_external_enter_i,
  input  logic        debug_resume_i,
  input  xlen_t       debug_external_dpc_i,
  input  logic        debug_csr_req_i,
  input  logic        debug_csr_write_i,
  input  logic [11:0] debug_csr_addr_i,
  input  xlen_t       debug_csr_wdata_i,
  output xlen_t       debug_csr_rdata_o,
  output logic        debug_csr_error_o,

  // HPM event observations
  input  logic        hpm_load_use_stall_i,
  input  logic        hpm_ifetch_wait_i,
  input  logic        hpm_dmem_stall_i,
  input  logic        hpm_wfi_wait_i,

  // M2 FPU completion and FCSR commit state
  input  logic         fpu_complete_valid_i,
  input  fp_complete_t fpu_complete_i,
  input  logic         fp_commit_i,
  input  logic         fp_dirty_i,
  input  logic [4:0]   fp_fflags_i,
  output logic [2:0]   fp_frm_o,
  output logic         fp_fs_off_o,

  // Hart-local MMU context exported from the CSR state.
  output xlen_t        satp_o,
  output privilege_mode_e privilege_mode_o,
  output logic         mstatus_sum_o,
  output logic         mstatus_mxr_o,
  output logic         mstatus_mprv_o,
  output privilege_mode_e mstatus_mpp_o,

  // Redirect and Debug-entry results
  output logic        branch_redirect_o,
  output xlen_t       branch_redirect_pc_o,
  output logic        trap_redirect_o,
  output xlen_t       trap_redirect_pc_o,
  output logic        debug_redirect_o,
  output xlen_t       debug_redirect_pc_o,
  output xlen_t       debug_dpc_o,
  output logic [2:0]  debug_cause_o,

  // Resolved conditional-branch outcome for ID-owned BHT training
  output logic        bht_update_valid_o,
  output xlen_t       bht_update_pc_o,
  output logic        bht_update_taken_o,

  // Resolved JAL/JALR maintenance for the ID-owned return-address stack
  output logic        ras_push_valid_o,
  output xlen_t       ras_push_addr_o,
  output logic        ras_pop_valid_o,

  output logic         control_event_o,
  output logic         wfi_redirect_o,
  output logic         muldiv_wait_o
);

  // EX/MEM boundary
  ex_mem_t ex_mem_d;

  // M2 FPU legality packet
  id_ex_t  trap_id_ex;

  // Current EX packet acceptance and serialized-control lifecycle
  logic    ex_accept;
  logic    ex_kill;
  logic    ex_complete;
  logic    control_event;
  control_source_e control_source;
  logic    control_exception;
  logic    control_mret;
  logic    control_sret;
  logic    control_debug_enter;
  logic    control_debug_step;
  logic    control_dret;
  logic    control_wfi;
  logic    control_sfence_vma;
  logic    sfence_vma_event;
  logic    control_allows_side_effects;
  logic    debug_enter;
  logic    wfi_legal;
  logic    wfi_event;

  // Forwarded operands and ALU data path
  xlen_t       rs1_data;
  xlen_t       rs2_data;
  logic        load_branch_rs1_match;
  logic        load_branch_rs2_match;
  logic        load_store_data_match;
  xlen_t       branch_operand_a;
  xlen_t       branch_operand_b;
  xlen_t       operand_a;
  xlen_t       operand_b;
  xlen_t       alu_result;
  // Load/store effective address has an isolated add path. It avoids
  // carrying the generic ALU operand-B selection and rs2 forwarding cone
  // into the DTCM and data-trigger paths.
  xlen_t       mem_addr;
  xlen_t       branch_target;
  xlen_t       jal_target;
  xlen_t       jalr_target;
  xlen_t       instr_next_pc;

  // Resolved control transfer and carried predictor result
  logic        branch_taken;
  logic        control_transfer_taken;
  logic        branch_redirect;
  logic        branch_prediction_active;
  logic        branch_prediction_miss;
  logic        return_prediction_active;
  logic        return_prediction_miss;
  logic        ras_push_instruction;
  logic        ras_pop_instruction;

  // CSR instruction transaction
  xlen_t       csr_rdata;
  xlen_t       csr_wdata;
  logic        csr_write_intent;
  logic        csr_access;
  logic        csr_illegal_access;

  // CSR trap-entry/return transaction
  logic        csr_trap_enter;
  xlen_t       csr_trap_pc;
  xlen_t       csr_trap_cause;
  xlen_t       csr_trap_value;
  logic        csr_trap_return;
  logic        csr_trap_sret;
  logic        csr_debug_enter;
  xlen_t       csr_debug_dpc;
  logic [2:0]  csr_debug_cause;
  logic [1:0]  instret_pending_count;

  // M2 FPU architectural-state view
  logic [2:0]  fp_frm;
  logic        fp_fs_off;

  // CSR-provided privilege and Debug state
  privilege_mode_e privilege_mode;
  privilege_mode_e mstatus_mpp;
  privilege_mode_e effective_data_privilege;
  logic        mstatus_tsr;
  logic        mstatus_tvm;
  logic        mstatus_sum;
  logic        mstatus_mxr;
  logic        mstatus_tw;
  logic        mstatus_mprv;
  logic [1:0]  menvcfg_cbie;
  logic        menvcfg_cbcfe;
  logic        cbo_illegal;
  cbo_op_e     cbo_effective_op;

  logic        ex_mem_data_access;
  xlen_t       mtvec;
  xlen_t       mepc;
  xlen_t       stvec;
  xlen_t       sepc;
  xlen_t       medeleg;
  xlen_t       trap_vector;
  xlen_t       dpc;
  logic        dcsr_step;
  logic        dcsr_ebreakm;
  logic [2:0]  dcsr_cause;

  // Trap and interrupt qualification
  logic        ebreak_debug_entry;
  logic        mret_trap;
  logic        dret_return;
  logic        sync_exception_trap;
  logic        interrupt_ready;
  logic        interrupt_to_s;
  xlen_t       interrupt_cause;
  logic        interrupt_trap;
  logic        exception_trap;
  logic        trap_to_s;
  logic        sret_return;
  xlen_t       trap_value;
  xlen_t       trap_cause;
  logic        mem_fault_to_s;

  // Debug single-step and trigger qualification
  logic        step_active_q;
  logic        step_debug_entry;
  xlen_t       step_dpc;
  xlen_t       debug_entry_dpc;
  logic [2:0]  debug_entry_cause;
  logic        ex_side_effects_en;
  xlen_t       trigger_mcontrol;
  xlen_t       trigger_tdata2;
  xlen_t       trigger_icount;
  xlen_t       trigger_match_value;
  logic        trigger_debug_entry;
  logic        debug_exception_entry;
  logic        trigger_retire;
  logic        mcontrol_hit;
  logic        icount_hit;

  // Iterative multiply/divide transaction
  logic        muldiv_start;
  logic        muldiv_busy;
  logic        muldiv_done;
  xlen_t       muldiv_result;

  localparam int HPM_EVENT_INDEX_W = (HPM_EVENT_COUNT > 1) ? $clog2(HPM_EVENT_COUNT) : 1;

  // HPM event vector committed by csr_file
  logic [HPM_EVENT_COUNT-1:0] hpm_event;

  // ---------------------------------------------------------------------------
  // EX acceptance and data path
  // ---------------------------------------------------------------------------
  // A full MEM stall freezes the EX/MEM boundary. Trap/debug/redirect side
  // effects must freeze with it so a stalled instruction cannot redirect fetch
  // or update CSRs before its packet is allowed to advance.
  assign ex_side_effects_en = ex_mem_en_i && !mem_fault_valid_i;
  assign ex_accept = id_ex_i.valid && ex_side_effects_en;

  // M1's iterative unit starts independently of the EX/MEM enable. This lets
  // the first cycle freeze the instruction in ID/EX while the operation starts.
  assign muldiv_start = id_ex_i.valid && id_ex_i.muldiv_en && !muldiv_busy && !muldiv_done;
  assign muldiv_wait_o = id_ex_i.valid && id_ex_i.muldiv_en && !muldiv_done;

  // Forwarding resolves all register operands before ALU, branch, mul/div,
  // store, and CSR RMW paths consume them.
  forwarding_unit forwarding_unit_i (
    .rs1_addr_i (id_ex_i.rs1_addr),
    .rs1_data_i (id_ex_i.rs1_data),
    .rs2_addr_i (id_ex_i.rs2_addr),
    .rs2_data_i (id_ex_i.rs2_data),
    .ex_mem_i   (ex_mem_fwd_i),
    .mem_wb_i   (mem_wb_fwd_i),
    .rs1_data_o (rs1_data),
    .rs2_data_o (rs2_data)
  );

  // The current MEM response is useful only to consumers explicitly admitted
  // by the top-level load-use policy. Keep it out of the common operand
  // forwarding network so branch dependencies do not fan into ALU, CSR,
  // mul/div, JALR, store-data, or address-generation paths. Store-data bypass
  // is carried as metadata and selected at the following MEM boundary.
  assign load_branch_rs1_match = (id_ex_i.branch_op != BR_NONE) &&
                                 load_result_bypass_valid_i &&
                                 (load_result_bypass_rd_addr_i != 5'd0) &&
                                 (load_result_bypass_rd_addr_i == id_ex_i.rs1_addr);
  assign load_branch_rs2_match = (id_ex_i.branch_op != BR_NONE) &&
                                 load_result_bypass_valid_i &&
                                 (load_result_bypass_rd_addr_i != 5'd0) &&
                                 (load_result_bypass_rd_addr_i == id_ex_i.rs2_addr);
  assign load_store_data_match = id_ex_i.mem_store && !id_ex_i.fp_access &&
                                 load_result_bypass_valid_i &&
                                 (load_result_bypass_rd_addr_i != 5'd0) &&
                                 (load_result_bypass_rd_addr_i == id_ex_i.rs2_addr);

  assign branch_operand_a = load_branch_rs1_match ? load_result_bypass_data_i : rs1_data;
  assign branch_operand_b = load_branch_rs2_match ? load_result_bypass_data_i : rs2_data;

  always_comb begin
    unique case (id_ex_i.op_a_sel)
      OP_A_PC:   operand_a = id_ex_i.pc;
      OP_A_ZERO: operand_a = '0;
      default:   operand_a = rs1_data;
    endcase
    unique case (id_ex_i.op_b_sel)
      OP_B_IMM:  operand_b = id_ex_i.imm;
      OP_B_FOUR: operand_b = id_ex_i.compressed ? xlen_t'(2) : xlen_t'(4);
      default:   operand_b = rs2_data;
    endcase
  end

  muldiv_unit #(
    .XLEN_P       (CORE_XLEN),
    .MUL_ITER_BITS(MUL_ITER_BITS_P)
  ) muldiv_unit_i (
    .clk         (clk),
    .rst_n       (rst_n),
    .start_i     (muldiv_start),
    .op_i        (id_ex_i.muldiv_op),
    .word_op_i   (id_ex_i.word_op),
    .operand_a_i (rs1_data),
    .operand_b_i (rs2_data),
    .busy_o      (muldiv_busy),
    .done_o      (muldiv_done),
    .result_o    (muldiv_result)
  );

  alu alu_i (
    .i_alu_op    (id_ex_i.alu_op),
    .i_operand_a (operand_a),
    .i_operand_b (operand_b),
    .o_result    (alu_result)
  );

  // Load/store addressing is always forwarded rs1 plus the decoded
  // immediate. Keep this physically independent from the general ALU so the
  // D-side address path does not inherit non-memory operand selection logic.
  assign mem_addr = rs1_data + id_ex_i.imm;

  branch_unit branch_unit_i (
    .i_branch_op (id_ex_i.branch_op),
    .i_operand_a (branch_operand_a),
    .i_operand_b (branch_operand_b),
    .o_taken     (branch_taken)
  );

  assign branch_target = id_ex_i.pc + id_ex_i.imm;
  assign jal_target    = id_ex_i.pc + id_ex_i.imm;
  assign jalr_target   = (rs1_data + id_ex_i.imm) & ~xlen_t'(1);
  assign instr_next_pc = id_ex_i.pc + (id_ex_i.compressed ? xlen_t'(2) : xlen_t'(4));

  // ---------------------------------------------------------------------------
  // Memory-access qualification.
  // ---------------------------------------------------------------------------
  assign ex_mem_data_access = ex_complete && control_allows_side_effects &&
                              (id_ex_i.mem_load || id_ex_i.mem_store ||
                               (id_ex_i.atomic_op != ATOMIC_NONE) ||
                               (id_ex_i.cbo_op != CBO_NONE));

  // CBO instructions use the store translation/protection path. menvcfg
  // controls S-mode use; U-mode remains disabled until senvcfg is added.
  always_comb begin
    cbo_illegal = 1'b0;
    cbo_effective_op = id_ex_i.cbo_op;
    if (id_ex_i.cbo_op != CBO_NONE) begin
      unique case (privilege_mode)
        PRIV_M: ;
        PRIV_S: begin
          if (id_ex_i.cbo_op == CBO_INVAL) begin
            unique case (menvcfg_cbie)
              MENVCFG_CBIE_FLUSH: cbo_effective_op = CBO_FLUSH;
              MENVCFG_CBIE_INVAL: ;
              default: cbo_illegal = 1'b1;
            endcase
          end else if (!menvcfg_cbcfe) begin
            cbo_illegal = 1'b1;
          end
        end
        default: cbo_illegal = 1'b1;
      endcase
    end
  end

  // M2 FPU legality is independent of memory-protection policy.
  always_comb begin
    trap_id_ex = id_ex_i;
    if ((id_ex_i.fp_access && fp_fs_off) ||
        (id_ex_i.fp_op && ((id_ex_i.fp_rounding_dynamic ? fp_frm : id_ex_i.fp_rounding_mode) > 3'b100))) begin
      trap_id_ex.illegal_instr = 1'b1;
    end
    if (cbo_illegal)
      trap_id_ex.illegal_instr = 1'b1;
  end

  // ---------------------------------------------------------------------------
  // Trap and Debug qualification
  // ---------------------------------------------------------------------------
  trap_control trap_control_i (
    // Current EX packet and acceptance gate
    .id_ex_i                    (trap_id_ex),
    .ex_accept_i                (ex_accept),
    .ex_side_effects_en_i       (ex_side_effects_en),
    // Privilege, Debug, and CSR execution context
    .debug_mode_i               (debug_mode_i),
    .privilege_mode_i           (privilege_mode),
    .mstatus_tw_i               (mstatus_tw),
    .mstatus_tsr_i              (mstatus_tsr),
    .mstatus_tvm_i              (mstatus_tvm),
    .medeleg_i                  (medeleg),
    .csr_illegal_access_i       (csr_illegal_access),
    .dcsr_ebreakm_i             (dcsr_ebreakm),
    // Resolved EX data result
    .alu_result_i               ((id_ex_i.mem_load || id_ex_i.mem_store ||
                                  (id_ex_i.atomic_op != ATOMIC_NONE) ||
                                  (id_ex_i.cbo_op != CBO_NONE)) ? mem_addr : alu_result),
    // Instruction-side translation/access faults and interrupt arbitration
    .instruction_page_fault_i   (id_ex_i.instruction_page_fault),
    .instruction_access_fault_i (id_ex_i.instruction_access_fault),
    .interrupt_ready_i          (interrupt_ready),
    .interrupt_to_s_i           (interrupt_to_s),
    .interrupt_cause_i          (interrupt_cause),
    // Debug and architectural-return outcomes
    .ebreak_debug_entry_o       (ebreak_debug_entry),
    .mret_trap_o                (mret_trap),
    .sret_return_o              (sret_return),
    .dret_return_o              (dret_return),
    // Trap classification and WFI legality
    .sync_exception_trap_o      (sync_exception_trap),
    .interrupt_trap_o           (interrupt_trap),
    .exception_trap_o           (exception_trap),
    .trap_to_s_o                (trap_to_s),
    .wfi_legal_o                (wfi_legal),
    .trap_cause_o               (trap_cause),
    .trap_value_o               (trap_value)
  );

  // ---------------------------------------------------------------------------
  // Debug trigger qualification
  // ---------------------------------------------------------------------------
  // Debug trigger qualification is EX-local: match the configured data or
  // address operand, then leave entry arbitration below with the other EX
  // outcomes. M1 retains the same trigger policy as M0.
  assign trigger_match_value = trigger_mcontrol[19] ? rs2_data :
                               ((id_ex_i.mem_load || id_ex_i.mem_store ||
                                 (id_ex_i.atomic_op != ATOMIC_NONE) ||
                                 (id_ex_i.cbo_op != CBO_NONE)) ? mem_addr : id_ex_i.pc);
  assign mcontrol_hit = ex_accept && !debug_mode_i &&
                        (((id_ex_i.mem_load && (id_ex_i.atomic_op == ATOMIC_NONE)) ||
                          (id_ex_i.atomic_op == ATOMIC_LR)) && trigger_mcontrol[0] ||
                         ((id_ex_i.mem_store || ((id_ex_i.atomic_op != ATOMIC_NONE) &&
                           (id_ex_i.atomic_op != ATOMIC_LR)) ||
                          (id_ex_i.cbo_op != CBO_NONE)) && trigger_mcontrol[1]) ||
                         (!id_ex_i.mem_load && !id_ex_i.mem_store &&
                          (id_ex_i.atomic_op == ATOMIC_NONE) &&
                          (id_ex_i.cbo_op == CBO_NONE) && trigger_mcontrol[2])) &&
                        (trigger_match_value == trigger_tdata2);
  assign icount_hit = ex_accept && !debug_mode_i &&
                      (trigger_icount[13:0] == 14'd1);

  assign trigger_debug_entry = (mcontrol_hit || icount_hit) &&
                               !exception_trap &&
                               !mret_trap && !sret_return && !dret_return && !ebreak_debug_entry;
  // EBREAK and trigger hits enter Debug before EX/MEM completes. Single-step
  // remains separate because it observes the completed instruction.
  assign debug_exception_entry = ebreak_debug_entry | trigger_debug_entry;

  // ---------------------------------------------------------------------------
  // EX outcome arbitration and architectural side effects
  // Redirects are stall-gated so jumps/branches cannot fire early and strand
  // their own link/writeback state behind a held EX/MEM register.
  // ---------------------------------------------------------------------------
  // trap_control includes S-mode TVM/U-mode legality. A synchronous trap
  // suppresses the architectural SFENCE.VMA packet.
  assign sfence_vma_event = ex_accept && (id_ex_i.sys_op == SYS_SFENCE_VMA) &&
                            !exception_trap;
  assign ex_kill = exception_trap | mret_trap | sret_return | dret_return |
                   debug_exception_entry | wfi_event | sfence_vma_event;
  // A completed EX instruction may enter MEM/WB or issue a normal control-flow
  // redirect. Trap and Debug outcomes instead consume the instruction here.
  assign ex_complete = ex_accept && !ex_kill &&
                       (!id_ex_i.fp_op || fpu_complete_valid_i);
  assign control_transfer_taken = ex_complete &&
                                  ((id_ex_i.branch_op != BR_NONE && branch_taken) ||
                                   (id_ex_i.jump_op != JUMP_NONE));
  assign branch_prediction_active = id_ex_i.branch_pred_valid &&
                                    (id_ex_i.branch_op != BR_NONE);
  assign branch_prediction_miss = ex_complete && branch_prediction_active &&
                                  (branch_taken != id_ex_i.branch_pred_taken);
  assign return_prediction_active = id_ex_i.return_pred_valid &&
                                    (id_ex_i.jump_op == JUMP_JALR);
  assign return_prediction_miss = ex_complete && return_prediction_active &&
                                  (jalr_target != id_ex_i.return_pred_target);
  // Training is EX-to-ID registered state only. It is deliberately not part
  // of the branch redirect or current-cycle predictor query path.
  assign bht_update_valid_o = ex_complete && (id_ex_i.branch_op != BR_NONE);
  assign bht_update_pc_o = id_ex_i.pc;
  assign bht_update_taken_o = branch_taken;
  assign ras_push_instruction = ((id_ex_i.jump_op == JUMP_JAL) ||
                                 (id_ex_i.jump_op == JUMP_JALR)) &&
                                ((id_ex_i.rd_addr == 5'd1) ||
                                 (id_ex_i.rd_addr == 5'd5));
  assign ras_pop_instruction = (id_ex_i.jump_op == JUMP_JALR) &&
                               (id_ex_i.rd_addr == 5'd0) &&
                               ((id_ex_i.rs1_addr == 5'd1) ||
                                (id_ex_i.rs1_addr == 5'd5)) &&
                               (id_ex_i.imm == '0);
  assign ras_push_valid_o = ex_complete && ras_push_instruction;
  assign ras_push_addr_o = instr_next_pc;
  assign ras_pop_valid_o = ex_complete && ras_pop_instruction;
  // A direct JAL requested by ID and a correctly predicted conditional branch
  // need no second frontend redirect in EX. C.J arrives decompressed;
  // JALR/C.JALR remain EX-resolved.
  assign branch_redirect = return_prediction_miss || branch_prediction_miss ||
                           (control_transfer_taken && !branch_prediction_active &&
                            !(id_ex_i.jump_op == JUMP_JAL && id_ex_i.jal_early) &&
                            !(id_ex_i.jump_op == JUMP_JALR && return_prediction_active));
  assign branch_redirect_o = branch_redirect;

  always_comb begin
    branch_redirect_pc_o = branch_target;
    if (return_prediction_miss) begin
      branch_redirect_pc_o = jalr_target;
    end else if (branch_prediction_miss && id_ex_i.branch_pred_taken) begin
      branch_redirect_pc_o = instr_next_pc;
    end else begin
      unique case (id_ex_i.jump_op)
        JUMP_JAL:  branch_redirect_pc_o = jal_target;
        JUMP_JALR: branch_redirect_pc_o = jalr_target;
        default:   branch_redirect_pc_o = branch_target;
      endcase
    end
  end

  assign step_dpc = control_transfer_taken ? branch_redirect_pc_o : instr_next_pc;
  assign step_debug_entry = step_active_q && ex_accept && !debug_mode_i &&
                            !exception_trap && !mret_trap && !sret_return && !dret_return &&
                            !ebreak_debug_entry;
  // WFI is a serializing control event. Its successor redirect is resolved
  // in EX, while the sleep state changes only when the packet reaches WB.
  assign wfi_event = ex_accept && (id_ex_i.sys_op == SYS_WFI) && wfi_legal;

  // Make the serialized-control causes mutually exclusive before encoding
  // their MEM/WB metadata. This keeps common control booleans out of the
  // priority encoder and documents the architectural arbitration directly.
  assign control_exception   = exception_trap;
  assign control_mret        = !control_exception && mret_trap;
  assign control_sret        = !control_exception && !control_mret && sret_return;
  assign control_debug_enter = !control_exception && !control_mret && !control_sret &&
                               debug_exception_entry;
  assign control_debug_step  = !control_exception && !control_mret && !control_sret &&
                               !control_debug_enter && step_debug_entry;
  assign control_dret        = !control_exception && !control_mret && !control_sret &&
                               !control_debug_enter && !control_debug_step &&
                               dret_return;
  assign control_wfi         = !control_exception && !control_mret && !control_sret &&
                               !control_debug_enter && !control_debug_step && !control_dret &&
                               wfi_event;
  assign control_sfence_vma  = !control_exception && !control_mret && !control_sret &&
                               !control_debug_enter && !control_debug_step && !control_dret &&
                               !control_wfi && sfence_vma_event;

  always_comb begin
    control_source = CONTROL_NONE;
    if (control_exception)
      control_source = CONTROL_EXCEPTION;
    else if (control_mret)
      control_source = CONTROL_MRET;
    else if (control_sret)
      control_source = CONTROL_SRET;
    else if (control_debug_enter)
      control_source = CONTROL_DEBUG_ENTER;
    else if (control_debug_step)
      control_source = CONTROL_DEBUG_STEP;
    else if (control_dret)
      control_source = CONTROL_DRET;
    else if (control_wfi)
      control_source = CONTROL_WFI;
    else if (control_sfence_vma)
      control_source = CONTROL_SFENCE_VMA;
  end
  assign control_event = control_exception | control_mret | control_sret |
                         control_debug_enter | control_debug_step | control_dret |
                         control_wfi | control_sfence_vma;
  // A single-step Debug entry retires the triggering instruction. All other
  // serialized control packets suppress its architectural side effects.
  // Keep this local predicate separate from control_source: the enum is
  // pipeline metadata, not a prerequisite for the EX side-effect cone.
  assign control_allows_side_effects = !control_event | control_debug_step;
  assign control_event_o = control_event;
  assign wfi_redirect_o  = control_wfi;
  assign trap_vector          = trap_to_s ? stvec : mtvec;
  assign mem_fault_to_s       = (privilege_mode != PRIV_M) &&
                                medeleg[mem_fault_cause_i[5:0]];
  assign mem_fault_redirect_o = mem_fault_valid_i;
  assign mem_fault_redirect_pc_o = mem_fault_to_s ?
                                      {stvec[CORE_XLEN-1:2], 2'b00} :
                                      {mtvec[CORE_XLEN-1:2], 2'b00};
  assign trap_redirect_o      = exception_trap | mret_trap | sret_return;
  assign trap_redirect_pc_o   = mret_trap ? mepc :
                                sret_return ? sepc :
                                ((interrupt_trap &&
                                  (trap_vector[1:0] == 2'b01)) ?
                                 ({trap_vector[CORE_XLEN-1:2], 2'b00} +
                                  ((interrupt_cause & ~(xlen_t'(1) << (CORE_XLEN-1))) << 2)) :
                                 {trap_vector[CORE_XLEN-1:2], 2'b00});
  assign debug_enter          = debug_external_enter_i | debug_exception_entry | step_debug_entry;
  assign debug_redirect_o     = debug_exception_entry | step_debug_entry | dret_return;
  assign debug_redirect_pc_o  = dret_return ? dpc :
                                DEBUG_BASE_ADDR_P;
  assign debug_entry_dpc      = debug_external_enter_i ? debug_external_dpc_i :
                                trigger_debug_entry ? id_ex_i.pc :
                                step_debug_entry ? step_dpc :
                                instr_next_pc;
  assign debug_entry_cause    = debug_external_enter_i ? 3'd1 :
                                ebreak_debug_entry ? 3'd2 :
                                trigger_debug_entry ? 3'd2 :
                                3'd4;
  assign debug_dpc_o          = dpc;
  assign debug_cause_o        = dcsr_cause;

  // ---------------------------------------------------------------------------
  // HPM event generation
  // ---------------------------------------------------------------------------
  always_comb begin
    hpm_event = '0;
    hpm_event[HPM_EVENT_BRANCH_RETIRED[HPM_EVENT_INDEX_W-1:0]]        = ex_complete &&
                                                  (id_ex_i.branch_op != BR_NONE);
    hpm_event[HPM_EVENT_BRANCH_TAKEN[HPM_EVENT_INDEX_W-1:0]]          = ex_complete && (id_ex_i.branch_op != BR_NONE) && branch_taken;
    hpm_event[HPM_EVENT_CONTROL_TRANSFER_RETIRED[HPM_EVENT_INDEX_W-1:0]] =
        (ex_complete && (id_ex_i.jump_op != JUMP_NONE)) || mret_trap || sret_return;
    hpm_event[HPM_EVENT_EXCEPTION_TAKEN[HPM_EVENT_INDEX_W-1:0]]       = sync_exception_trap;
    hpm_event[HPM_EVENT_INTERRUPT_TAKEN[HPM_EVENT_INDEX_W-1:0]]       = interrupt_trap;
    hpm_event[HPM_EVENT_IFETCH_WAIT_CYCLES[HPM_EVENT_INDEX_W-1:0]]    = hpm_ifetch_wait_i;
    hpm_event[HPM_EVENT_DATA_WAIT_CYCLES[HPM_EVENT_INDEX_W-1:0]]      = hpm_dmem_stall_i;
    hpm_event[HPM_EVENT_PIPELINE_STALL_CYCLES[HPM_EVENT_INDEX_W-1:0]] = hpm_load_use_stall_i ||
                                                  hpm_ifetch_wait_i || hpm_dmem_stall_i;
    hpm_event[HPM_EVENT_LOAD_USE_STALL_CYCLES[HPM_EVENT_INDEX_W-1:0]] = hpm_load_use_stall_i;
    hpm_event[HPM_EVENT_WFI_CYCLES[HPM_EVENT_INDEX_W-1:0]]            = hpm_wfi_wait_i;
    hpm_event[HPM_EVENT_DEBUG_ENTRY[HPM_EVENT_INDEX_W-1:0]]           = debug_enter;
    hpm_event[HPM_EVENT_IRQ_PENDING_CYCLES[HPM_EVENT_INDEX_W-1:0]]    = |irq_i;
  end

  // ---------------------------------------------------------------------------
  // CSR architectural state
  // The current CSR view feeds trap/Debug qualification above. Final EX
  // outcomes below its inputs are committed only on the clock edge.
  // ---------------------------------------------------------------------------
  // CSR RMW input is formed after forwarding so CSRRS/CSRRC observe the
  // youngest producer in the same way as the ALU operand path.
  assign csr_wdata = id_ex_i.csr_use_imm ? xlen_t'(id_ex_i.csr_imm) : rs1_data;
  assign csr_write_intent = (id_ex_i.csr_op == CSR_OP_WRITE) ||
                            (((id_ex_i.csr_op == CSR_OP_SET) || (id_ex_i.csr_op == CSR_OP_CLEAR)) &&
                             (id_ex_i.csr_use_imm ? (id_ex_i.csr_imm != 5'd0) :
                                                   (id_ex_i.rs1_addr != 5'd0)));
  assign csr_access     = ex_accept && id_ex_i.csr_access;
  // Trap and Debug CSR state changes are consumed only from the WB-aligned
  // control packet.  EX still resolves the redirect, but never exposes a
  // handler to partially updated architectural state.
  assign csr_trap_enter  = control_trap_enter_i;
  assign csr_trap_pc     = control_trap_pc_i;
  assign csr_trap_cause  = control_trap_cause_i;
  assign csr_trap_value  = control_trap_value_i;
  assign csr_trap_return = control_trap_return_i;
  assign csr_trap_sret   = control_sret_return_i;

  // An external halt enters Debug immediately; otherwise consume the retired
  // Debug control packet from WB. Keep this arbitration outside the CSR port
  // map so the instance connects only named transaction signals.
  assign csr_debug_enter = control_debug_enter_i | debug_external_enter_i;
  assign csr_debug_dpc   = debug_external_enter_i ? debug_external_dpc_i :
                           control_debug_dpc_i;
  assign csr_debug_cause = debug_external_enter_i ? 3'd1 : control_debug_cause_i;

  // `minstret` shares the EX completion boundary with CSR reads.
  assign instret_pending_count = 2'd0;

  // A trigger counter observes accepted instruction completion. Preserve the
  // existing exception, return, and EBREAK exclusions.
  assign trigger_retire = ex_accept && !debug_mode_i &&
                          !exception_trap && !mret_trap && !sret_return && !dret_return &&
                          !ebreak_debug_entry;

  csr_file #(
    .RESET_VECTOR_ADDR_P(RESET_VECTOR_ADDR_P)
  ) csr_file_i (
    // Clock and reset
    .clk                  (clk),
    .rst_n                (rst_n),
    // Executing CSR instruction transaction. Keep CSR reads/writes aligned
    // with the same stall gate as traps and redirects so handler-visible state
    // matches the instruction stream.
    .csr_access_i         (csr_access),
    .csr_op_i             (id_ex_i.csr_op),
    .csr_addr_i           (id_ex_i.csr_addr),
    .csr_write_intent_i   (csr_write_intent),
    .csr_wdata_i          (csr_wdata),
    .csr_rdata_o          (csr_rdata),
    .csr_illegal_access_o (csr_illegal_access),
    // Trap entry and return
    .trap_enter_i         (csr_trap_enter),
    .trap_pc_i            (csr_trap_pc),
    .trap_cause_i         (csr_trap_cause),
    .trap_value_i         (csr_trap_value),
    .trap_return_i        (csr_trap_return),
    .trap_sret_i          (csr_trap_sret),
    // Debug entry and run state
    .debug_enter_i        (csr_debug_enter),
    .debug_dpc_i          (csr_debug_dpc),
    .debug_cause_i        (csr_debug_cause),
    .debug_mode_i         (debug_mode_i),
    // Retirement, time, interrupt, and HPM event observations
    .retire_i             (ex_complete),
    .instret_pending_i    (instret_pending_count),
    .irq_i                (irq_i),
    .mtime_i              (mtime_i),
    .hpm_event_i          (hpm_event),
    .fp_commit_i          (fp_commit_i),
    .fp_dirty_i           (fp_dirty_i),
    .fp_fflags_i          (fp_fflags_i),
    .frm_o                (fp_frm),
    .fs_off_o             (fp_fs_off),

    // Debug abstract CSR transaction
    .debug_csr_req_i      (debug_csr_req_i),
    .debug_csr_write_i    (debug_csr_write_i),
    .debug_csr_addr_i     (debug_csr_addr_i),
    .debug_csr_wdata_i    (debug_csr_wdata_i),
    .debug_csr_rdata_o    (debug_csr_rdata_o),
    .debug_csr_error_o    (debug_csr_error_o),
    // Trigger retirement observation and state views
    .trigger_retire_i     (trigger_retire),
    .trigger_mcontrol_o   (trigger_mcontrol),
    .trigger_tdata2_o     (trigger_tdata2),
    .trigger_icount_o     (trigger_icount),
    // Architectural trap and Debug state views
    .mtvec_o              (mtvec),
    .mepc_o               (mepc),
    .stvec_o              (stvec),
    .sepc_o               (sepc),
    .medeleg_o            (medeleg),
    .dpc_o                (dpc),
    .dcsr_step_o          (dcsr_step),
    .dcsr_ebreakm_o       (dcsr_ebreakm),
    .dcsr_cause_o         (dcsr_cause),
    // Interrupt arbitration result
    .interrupt_ready_o    (interrupt_ready),
    .interrupt_to_s_o     (interrupt_to_s),
    .interrupt_cause_o    (interrupt_cause),
    .privilege_mode_o     (privilege_mode),
    .mstatus_tsr_o        (mstatus_tsr),
    .mstatus_tw_o         (mstatus_tw),
    .mstatus_mprv_o       (mstatus_mprv),
    .mstatus_mpp_o        (mstatus_mpp),
    .mstatus_tvm_o        (mstatus_tvm),
    .mstatus_sum_o        (mstatus_sum),
    .mstatus_mxr_o        (mstatus_mxr),
    .menvcfg_cbie_o      (menvcfg_cbie),
    .menvcfg_cbcfe_o     (menvcfg_cbcfe),
    .satp_o               (satp_o)
  );

  assign fp_frm_o = fp_frm;
  assign fp_fs_off_o = fp_fs_off;
  assign privilege_mode_o = privilege_mode;
  assign mstatus_sum_o = mstatus_sum;
  assign mstatus_mxr_o = mstatus_mxr;
  assign mstatus_mprv_o = mstatus_mprv;
  assign mstatus_mpp_o = mstatus_mpp;

  // ---------------------------------------------------------------------------
  // EX/MEM packet and local sequential state
  // ---------------------------------------------------------------------------
  always_comb begin
    ex_mem_d = '0;
    // Serialized trap/Debug/WFI packets use the existing EX/MEM and MEM/WB
    // boundaries but are explicitly excluded from architectural retirement.
    ex_mem_d.valid     = ex_complete | control_event;
    ex_mem_d.control_source      = control_source;
    ex_mem_d.pc        = id_ex_i.pc;
    ex_mem_d.instr     = id_ex_i.instr;
    ex_mem_d.control_trap_pc    = id_ex_i.pc;
    ex_mem_d.control_trap_cause = trap_cause;
    ex_mem_d.control_trap_value = trap_value;
    ex_mem_d.control_debug_dpc  = debug_entry_dpc;
    ex_mem_d.control_debug_cause = debug_entry_cause;
    ex_mem_d.control_sfence_vma_vaddr = rs1_data;
    ex_mem_d.control_sfence_vma_asid = rs2_data[15:0];
    ex_mem_d.compressed = id_ex_i.compressed;
    ex_mem_d.ex_result = id_ex_i.fp_op ? xlen_t'(fpu_complete_i.result) :
                         id_ex_i.csr_access ? csr_rdata :
                         id_ex_i.muldiv_en ? muldiv_result : alu_result;
    ex_mem_d.data_addr = mem_addr;
    ex_mem_d.store_data = id_ex_i.mem_store && !id_ex_i.fp_op &&
                          (id_ex_i.instr[6:0] == 7'b010_0111) ?
                          xlen_t'(id_ex_i.fp_rs2_data) : rs2_data;
    ex_mem_d.store_rs2_addr = id_ex_i.rs2_addr;
    ex_mem_d.load_store_data_bypass = load_store_data_match;
    ex_mem_d.fence     = ex_mem_d.valid && control_allows_side_effects &&
                         id_ex_i.fence;
    ex_mem_d.cbo_op    = (ex_mem_d.valid && control_allows_side_effects) ?
                         cbo_effective_op : CBO_NONE;
    ex_mem_d.rd_addr   = id_ex_i.rd_addr;
    ex_mem_d.mem_load  = ex_mem_d.valid && control_allows_side_effects &&
                         id_ex_i.mem_load;
    ex_mem_d.mem_store = ex_mem_d.valid && control_allows_side_effects &&
                         id_ex_i.mem_store;
    ex_mem_d.mem_type  = id_ex_i.mem_type;
    ex_mem_d.atomic_op = (ex_mem_d.valid && control_allows_side_effects) ?
                          id_ex_i.atomic_op : ATOMIC_NONE;
    ex_mem_d.atomic_aq = id_ex_i.atomic_aq;
    ex_mem_d.atomic_rl = id_ex_i.atomic_rl;
    ex_mem_d.fp_write  = ex_mem_d.valid && id_ex_i.fp_write;
    ex_mem_d.fp_dirty  = ex_mem_d.valid && id_ex_i.fp_access;
    ex_mem_d.fp_dst_fmt = id_ex_i.fp_dst_fmt;
    ex_mem_d.fp_rd_addr = id_ex_i.rd_addr;
    ex_mem_d.fp_fflags = id_ex_i.fp_op ? fpu_complete_i.fflags : 5'd0;
    ex_mem_d.rd_we     = ex_mem_d.valid && control_allows_side_effects &&
                         id_ex_i.rd_we;
    ex_mem_d.wb_sel    = id_ex_i.wb_sel;
  end

  // Publish the EX result only when the EX/MEM boundary advances.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ex_mem_o <= '0;
    end else if (ex_mem_flush_i) begin
      ex_mem_o <= '0;
    end else if (ex_mem_en_i) begin
      // Only publish a new EX result when the pipeline boundary advances.
      ex_mem_o <= ex_mem_d;
    end
  end

  // Single-step becomes active after DRET or external resume and is consumed
  // by the next accepted instruction above.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      step_active_q <= 1'b0;
    end else if (debug_enter) begin
      step_active_q <= 1'b0;
    end else if (dret_return || debug_resume_i) begin
      step_active_q <= dcsr_step;
    end
  end

endmodule
