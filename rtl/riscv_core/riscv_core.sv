// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

import riscv_pkg::*;

// Phase 12 five-stage RV64 integer core top.
// It connects the pipeline stages, hazard control, debug flow, and memory-side handshakes.
//
// The core fetches 32-bit instruction words and exposes 48-bit physical
// addresses with a 64-bit data path. Memory size and address decoding belong
// to the surrounding SoC or verification wrapper.
module riscv_core #(
  parameter xlen_t RESET_VECTOR_ADDR_P = xlen_t'(RESET_VECTOR_ADDR),
  parameter xlen_t DEBUG_BASE_ADDR_P   = xlen_t'(DEBUG_BASE_ADDR),
  // Enable EX-stage local-memory load launch. When disabled, all data loads
  // use the normal MEM-stage D-bus path and the optional local port is idle.
  parameter bit          ENABLE_LMEM_EARLY_LOAD_P = 1'b1,
  // Enable completed-load forwarding to branch comparison and store data.
  // When disabled, dependent consumers wait for MEM/WB writeback.
  parameter bit          ENABLE_LOAD_RESPONSE_BYPASS_P = 1'b1,
  // Enable the dynamic BHT. When disabled, conditional branches use BTFNT.
  parameter bit          ENABLE_BHT_P = 1'b1,
  // Enable the return-address stack. When disabled, JALR resolves in EX.
  parameter bit          ENABLE_RAS_P = 1'b1,
  // Enable the sequential prefetch for an uncompressed instruction starting in an
  // IMEM response upper halfword.
  parameter bit          ENABLE_UPPER_32_PREFETCH_P = 1'b1,
  // Multiplier source bits consumed per iterative compute cycle.
  // Supported values are 1, 2, 4, 8, 16, and 32. The delivery SoC selects 16.
  parameter int unsigned MUL_ITER_BITS_P = 8
) (
  // Clock and reset
  input  logic        clk,
  input  logic        rst_n,

  // Fetch startup control
  input  logic        fetch_enable_i,
  input  xlen_t       boot_addr_i,

  // Debug control and abstract register access
  input  logic        debug_halt_req_i,
  input  logic        debug_resume_req_i,
  output logic        debug_halted_o,
  output logic        debug_running_o,
  output xlen_t       debug_pc_o,
  output logic [2:0]  debug_cause_o,
  input  logic        debug_reg_req_valid_i,
  input  logic        debug_reg_write_i,
  input  logic [15:0] debug_reg_addr_i,
  input  xlen_t       debug_reg_wdata_i,
  output xlen_t       debug_reg_rdata_o,
  output logic        debug_reg_error_o,

  // Instruction-memory interface
  output logic        imem_req_o,
  input  logic        imem_ready_i,
  output paddr_t      imem_addr_o,
  input  logic        imem_rvalid_i,
  input  logic [31:0] imem_rdata_i,

  // Data-memory interface
  output logic        data_req_o,
  output paddr_t      data_addr_o,
  output logic [63:0] data_wdata_o,
  output logic        data_we_o,
  output logic [7:0]  data_be_o,
  output atomic_op_e  data_atomic_op_o,
  output logic        data_atomic_aq_o,
  output logic        data_atomic_rl_o,
  input  logic        data_resp_valid_i,
  input  logic [63:0] data_rdata_i,
  input  logic        data_err_i,
  // FENCE cache-drain handshake. A cacheless integration may complete this
  // immediately once its blocking D-bus has completed all older accesses.
  output logic        data_fence_o,
  input  logic        data_fence_done_i,
  input  logic        data_fence_err_i,

  // Optional local-memory read request (core -> SoC).
  // The core does not decode the address map; an unaccepted request falls
  // back to the normal D-bus path.
  output logic        lmem_req_o,
  output paddr_t      lmem_addr_o,
  input  logic        lmem_accept_i,
  input  logic        lmem_resp_valid_i,
  input  logic [63:0] lmem_rdata_i,
  input  logic        lmem_err_i,

  // Time, interrupt, and WFI wake inputs
  input  logic [63:0] mtime_i,
  input  logic [31:0] irq_i,
  input  logic        wfi_wake_i,
  output logic        wfi_sleep_o
);

  // ---------------------------------------------------------------------------
  // Pipeline register state
  // ---------------------------------------------------------------------------
  if_id_t  if_id_q;
  id_ex_t  id_ex_q;
  ex_mem_t ex_mem_q;
  mem_wb_t mem_wb_q;

  // ---------------------------------------------------------------------------
  // IF-stage observations and decode dependency metadata
  // IF owns I-bus waiting; the source metadata is decoded alongside IF/ID.
  // ---------------------------------------------------------------------------
  paddr_t      if_imem_addr;
  xlen_t       if_halt_pc;
  logic        if_fetch_wait;
  logic        if_id_uses_rs1;
  logic        if_id_uses_rs2;
  logic [4:0]  if_id_rs1_addr;
  logic [4:0]  if_id_rs2_addr;
  logic        if_id_uses_frs1;
  logic        if_id_uses_frs2;
  logic        if_id_uses_frs3;
  logic [4:0]  if_id_frs1_addr;
  logic [4:0]  if_id_frs2_addr;
  logic [4:0]  if_id_frs3_addr;

  // MEM/WB observations, writeback data flow, and M1 D-bus adaptation
  // M1 separates I/D requests and can hold MEM/WB on a response wait.
  logic        mem_wait;
  logic        mem_lmem_response;

  // Optional EX-stage local-memory path. Keep the external port stable for
  // all configurations; the parameter disables request, acceptance, and
  // completion together so a disabled path cannot consume a local response.
  logic        lmem_req_internal;
  paddr_t      lmem_addr_internal;
  logic        lmem_accept;
  logic        lmem_resp_valid;
  logic [63:0] lmem_rdata;
  logic        lmem_err;

  generate
    if (ENABLE_LMEM_EARLY_LOAD_P) begin : g_lmem_early_load
      assign lmem_req_o      = lmem_req_internal;
      assign lmem_addr_o     = lmem_addr_internal;
      assign lmem_accept     = lmem_accept_i;
      assign lmem_resp_valid = lmem_resp_valid_i;
      assign lmem_rdata      = lmem_rdata_i;
      assign lmem_err        = lmem_err_i;
    end else begin : g_no_lmem_early_load
      assign lmem_req_o      = 1'b0;
      assign lmem_addr_o     = '0;
      assign lmem_accept     = 1'b0;
      assign lmem_resp_valid = 1'b0;
      assign lmem_rdata      = '0;
      assign lmem_err        = 1'b0;
    end
  endgenerate

  // EX/WB serialized-control lifecycle and architectural commit data
  logic        ex_control_event;
  logic        control_serialize_q;
  logic        control_commit;
  logic        control_trap_enter;
  logic        control_trap_return;
  logic        control_debug_enter;
  logic        control_debug_return;
  logic        control_wfi;
  xlen_t       control_trap_pc;
  xlen_t       control_trap_cause;
  xlen_t       control_trap_value;
  xlen_t       control_debug_dpc;
  logic [2:0]  control_debug_cause;

  // WB architectural GPR writeback
  logic [4:0]  wb_rd_addr;
  xlen_t       wb_rd_data;
  logic        wb_rd_we;

  // ---------------------------------------------------------------------------
  // Pipeline-control outputs and redirect sources
  // Redirects are arbitrated as trap > Debug > FENCE.I > WFI > branch/jump.
  // Flushes kill younger instructions; enables stall the pipeline boundary.
  // ---------------------------------------------------------------------------
  logic        pc_en;
  logic        if_id_en;
  logic        backend_advance;
  logic        if_id_flush;
  logic        id_ex_flush;
  logic        ex_mem_flush;

  // Pipeline-control stall and response observations
  logic        muldiv_wait;
  logic        load_use_stall;
  logic        mem_load_use_stall;
  logic        id_ex_replay_stall;
  logic        if_id_conditional_branch;
  logic        if_id_store_instruction;
  logic        load_bypass_eligible;
  logic        mem_load_response_ready;
  logic        load_response_bypass_valid;
  logic        load_store_data_bypass_eligible;
  logic        load_result_bypass_valid;
  logic [4:0]  load_result_bypass_rd_addr;
  xlen_t       load_result_bypass_data;

  // Redirect sources and resolved EX-stage redirect
  // Priority is trap > Debug > FENCE.I > WFI > branch/jump.
  logic        redirect_valid;
  xlen_t       redirect_pc;
  logic        branch_redirect;
  xlen_t       branch_redirect_pc;
  logic        id_predict_redirect;
  xlen_t       id_predict_redirect_pc;
  logic        fetch_redirect_valid;
  xlen_t       fetch_redirect_pc;
  logic        fence_i_redirect;
  xlen_t       fence_i_redirect_pc;
  logic        wfi_redirect;
  xlen_t       wfi_redirect_pc;
  // M1 U-mode only: trap_control clears this when mstatus.TW forbids WFI.
  // M0 is M-mode-only, so its corresponding condition is always legal.
  logic        trap_redirect;
  xlen_t       trap_redirect_pc;
  logic        debug_redirect;
  xlen_t       debug_redirect_pc;

  // Resolved EX conditional branches train the ID-owned BHT at the next edge.
  logic        bht_update_valid;
  xlen_t       bht_update_pc;
  logic        bht_update_taken;
  logic        ras_push_valid;
  xlen_t       ras_push_addr;
  logic        ras_pop_valid;

  // ---------------------------------------------------------------------------
  // Debug run state and abstract-access routing
  // ---------------------------------------------------------------------------
  xlen_t       debug_dpc;
  logic [2:0]  debug_cause;
  logic        debug_mode_q;
  logic        debug_halted_q;
  logic        debug_halt_pending_q;
  logic        debug_external_session_q;
  logic        debug_external_enter;
  logic        debug_resume_redirect;
  logic        frontend_run_enable;
  logic        effective_fetch_enable;
  logic        wfi_sleep_q;
  logic        wfi_wake;
  logic        pipeline_empty;
  logic        id_predict_enable;
  logic        debug_gpr_sel;
  logic        debug_csr_sel;
  logic        debug_gpr_write;
  logic        debug_csr_access;
  xlen_t       debug_gpr_rdata;
  xlen_t       debug_csr_rdata;
  logic        debug_csr_error;

  // FPU hazard qualification and pipeline stall
  logic        fpu_wait;
  logic        fp_load_use_stall;
  logic        mem_fp_load_use_stall;
  logic        fp_write_use_stall;
  logic        mem_fp_write_use_stall;

  // Debug abstract FPR access
  logic        debug_fpr_sel;
  logic        debug_fpr_write;
  logic [63:0] debug_fpr_rdata;

  // FPR writeback and FCSR retirement state
  logic        fp_wb_we;
  logic [4:0]  fp_wb_rd_addr;
  logic [63:0] fp_wb_data;
  logic [4:0]  fp_wb_fflags;
  logic        fp_wb_dirty;
  logic [2:0]  fp_frm;
  logic        fp_fs_off;
  logic        fp_rm_invalid;

  // One-outstanding-operation CVFPU adapter transport
  logic        fpu_issue_valid;
  logic        fpu_issue_ready;
  logic        fpu_busy;
  logic        fpu_complete_valid;
  logic        fpu_complete_ready;
  fp_issue_t   fpu_issue;
  fp_complete_t fpu_complete;

  // Integer rs1 forwarding for FP integer-convert and move operations
  xlen_t       fp_gpr_operand_a;

  // ---------------------------------------------------------------------------
  // Debug register address decode and access qualification
  // ---------------------------------------------------------------------------
  // An external halt enters Debug Mode only after all in-flight instructions
  // and memory responses drain. Debug instruction entry/return is generated
  // by EX; these state bits only control top-level fetch and Debug visibility.
  assign pipeline_empty = !if_id_q.valid && !id_ex_q.valid && !ex_mem_q.valid && !mem_wb_q.valid && !fpu_busy &&
                          !if_fetch_wait && !mem_wait;

  assign debug_gpr_sel = (debug_reg_addr_i >= 16'h1000) && (debug_reg_addr_i <= 16'h101f);
  assign debug_fpr_sel = (debug_reg_addr_i >= 16'h1020) && (debug_reg_addr_i <= 16'h103f);
  assign debug_csr_sel = (debug_reg_addr_i == {4'h0, CSR_DCSR}) ||
                         (debug_reg_addr_i == {4'h0, CSR_DPC}) ||
                         (debug_reg_addr_i == {4'h0, CSR_DSCRATCH0}) ||
                         (debug_reg_addr_i == {4'h0, CSR_DSCRATCH1}) ||
                         (debug_reg_addr_i == {4'h0, CSR_TSELECT}) ||
                         (debug_reg_addr_i == {4'h0, CSR_TDATA1}) ||
                         (debug_reg_addr_i == {4'h0, CSR_TDATA2});
  assign debug_reg_rdata_o = debug_gpr_sel ? debug_gpr_rdata :
                             debug_fpr_sel ? xlen_t'(debug_fpr_rdata) : debug_csr_rdata;
  assign debug_reg_error_o = debug_reg_req_valid_i &&
                             ((!debug_gpr_sel && !debug_fpr_sel && !debug_csr_sel) ||
                              (debug_csr_sel && debug_csr_error));
  assign debug_gpr_write = debug_reg_req_valid_i && debug_reg_write_i &&
                           debug_gpr_sel && debug_halted_q;
  assign debug_fpr_write = debug_reg_req_valid_i && debug_reg_write_i &&
                           debug_fpr_sel && debug_halted_q;
  assign debug_csr_access = debug_reg_req_valid_i && debug_csr_sel && debug_halted_q;

  // ---------------------------------------------------------------------------
  // WFI and Debug run-state control
  // ---------------------------------------------------------------------------
  // A cacheless FENCE.I still must discard any earlier prefetch. The older
  // store is already complete because a MEM response stalls in-order progress.
  // WFI changes architectural sleep state, so it remains locally suppressed.
  assign fence_i_redirect    = id_ex_q.valid && id_ex_q.fence_i && backend_advance;
  assign fence_i_redirect_pc = id_ex_q.pc + xlen_t'(4);
  // An illegal U-mode WFI reaches WB as a trap rather than a sleep event.
  // WB owns the control-source decode and exports these mutually exclusive
  // architectural actions directly.
  assign wfi_redirect_pc     = id_ex_q.pc + xlen_t'(4);
  assign wfi_sleep_o         = wfi_sleep_q;

  assign debug_external_enter   = debug_halt_pending_q && pipeline_empty;
  assign debug_resume_redirect  = debug_halted_q && debug_resume_req_i;
  assign wfi_wake               = wfi_wake_i || (|irq_i) || debug_halt_req_i || debug_resume_req_i;
  // Run-state gating common to IF issue and the ID predictor. An EX control
  // event suppresses a real IF transaction, but need not suppress a predictor
  // query: its result is overridden by the older EX redirect in the same cycle.
  assign frontend_run_enable = fetch_enable_i && !debug_halt_pending_q && !debug_halted_q &&
                               !wfi_sleep_q && !control_serialize_q;
  assign effective_fetch_enable = frontend_run_enable && !ex_control_event;
  // An EX redirect wins over ID prediction and flushes the ID/EX packet.
  // Keep the predictor eligible in that cycle so the resolved EX control
  // signal does not become a prerequisite of the predictor/RAS query.

  // WFI commits by redirecting to its successor, then blocks fetch until one
  // of the architectural wake sources is observed.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      wfi_sleep_q <= 1'b0;
    else if (wfi_wake)
      wfi_sleep_q <= 1'b0;
    else if (control_wfi)
      wfi_sleep_q <= 1'b1;
  end

  // External halt waits for the pipeline to drain. EX-generated Debug entry
  // and return update the same visible run state at instruction boundaries.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      debug_mode_q <= 1'b0;
      debug_halted_q <= 1'b0;
      debug_halt_pending_q <= 1'b0;
      debug_external_session_q <= 1'b0;
    end else begin
      if (debug_halt_req_i && !debug_halted_q)
        debug_halt_pending_q <= 1'b1;
      if (debug_external_enter) begin
        debug_mode_q <= 1'b1;
        debug_halted_q <= 1'b1;
        debug_halt_pending_q <= 1'b0;
        debug_external_session_q <= 1'b1;
      end else if (control_debug_enter) begin
        debug_mode_q <= 1'b1;
        debug_halted_q <= debug_external_session_q;
        debug_halt_pending_q <= 1'b0;
      end
      // Chain debug state transitions in a single priority path so no two
      // transitions can compete in the same cycle.
      else if (control_debug_return) begin
        debug_mode_q <= 1'b0;
        debug_halted_q <= 1'b0;
        debug_halt_pending_q <= 1'b0;
        debug_external_session_q <= 1'b0;
      end else if (debug_resume_redirect) begin
        debug_mode_q <= 1'b0;
        debug_halted_q <= 1'b0;
        debug_halt_pending_q <= 1'b0;
      end
    end
  end

  // Any EX control event redirects immediately, then prevents a successor
  // from entering the pipeline until its packet reaches WB. This gives
  // trap/Debug/WFI a single architectural consumption boundary without
  // adding latency to normal branch/jump/load/store flow.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      control_serialize_q <= 1'b0;
    else if (control_commit)
      control_serialize_q <= 1'b0;
    else if (ex_control_event)
      control_serialize_q <= 1'b1;
  end

  // ---------------------------------------------------------------------------
  // Decode hazard detection and pipeline action policy
  // ---------------------------------------------------------------------------
  // A dependent instruction normally stalls first for the load in ID/EX.
  // Branches and store-data-only consumers may enter EX behind a load. The
  // completed MEM response supplies their dedicated bypass; mem_wait freezes
  // them until that response is present. This avoids an EX/SoC-accept-to-IF
  // combinational control path.
  assign load_store_data_bypass_eligible =
      if_id_store_instruction && if_id_uses_rs2 &&
      (id_ex_q.rd_addr == if_id_rs2_addr) &&
      !(if_id_uses_rs1 && (id_ex_q.rd_addr == if_id_rs1_addr));
  generate
    if (ENABLE_LOAD_RESPONSE_BYPASS_P) begin : g_load_response_bypass
      assign load_bypass_eligible = if_id_conditional_branch ||
                                    load_store_data_bypass_eligible;
      assign mem_load_response_ready = data_resp_valid_i || mem_lmem_response;
      // The dedicated response bypass is an integer GPR path.  An FLW uses
      // the same memory transport but must retire through the FPR path only.
      assign load_response_bypass_valid = load_result_bypass_valid && !ex_mem_q.fp_write;
    end else begin : g_no_load_response_bypass
      assign load_bypass_eligible = 1'b0;
      assign mem_load_response_ready = 1'b0;
      assign load_response_bypass_valid = 1'b0;
    end
  endgenerate
  assign load_use_stall = if_id_q.valid && id_ex_q.valid && id_ex_q.mem_load && !id_ex_q.fp_write &&
                          (id_ex_q.rd_addr != 5'd0) &&
                          !load_bypass_eligible &&
                          ((if_id_uses_rs1 && (id_ex_q.rd_addr == if_id_rs1_addr)) ||
                           (if_id_uses_rs2 && (id_ex_q.rd_addr == if_id_rs2_addr)));

  assign mem_load_use_stall = if_id_q.valid && ex_mem_q.valid && ex_mem_q.mem_load && !ex_mem_q.fp_write &&
                              (ex_mem_q.rd_addr != 5'd0) &&
                              !mem_load_response_ready &&
                              ((if_id_uses_rs1 && (ex_mem_q.rd_addr == if_id_rs1_addr)) ||
                               (if_id_uses_rs2 && (ex_mem_q.rd_addr == if_id_rs2_addr)));
  assign fp_load_use_stall = if_id_q.valid && id_ex_q.valid && id_ex_q.mem_load && id_ex_q.fp_write &&
                             ((if_id_uses_frs1 && (id_ex_q.rd_addr == if_id_frs1_addr)) ||
                              (if_id_uses_frs2 && (id_ex_q.rd_addr == if_id_frs2_addr)) ||
                              (if_id_uses_frs3 && (id_ex_q.rd_addr == if_id_frs3_addr)));
  assign mem_fp_load_use_stall = if_id_q.valid && ex_mem_q.valid && ex_mem_q.mem_load && ex_mem_q.fp_write &&
                                 ((if_id_uses_frs1 && (ex_mem_q.fp_rd_addr == if_id_frs1_addr)) ||
                                  (if_id_uses_frs2 && (ex_mem_q.fp_rd_addr == if_id_frs2_addr)) ||
                                  (if_id_uses_frs3 && (ex_mem_q.fp_rd_addr == if_id_frs3_addr)));

  // All FPR writers, not just FLW, must retire before a dependent FP reader
  // captures its operand in ID.  The final MEM/WB cycle is covered by the
  // existing FPR write-through bypass in id_stage.
  assign fp_write_use_stall = if_id_q.valid && id_ex_q.valid && id_ex_q.fp_write && !id_ex_q.mem_load &&
                              ((if_id_uses_frs1 && (id_ex_q.rd_addr == if_id_frs1_addr)) ||
                               (if_id_uses_frs2 && (id_ex_q.rd_addr == if_id_frs2_addr)) ||
                               (if_id_uses_frs3 && (id_ex_q.rd_addr == if_id_frs3_addr)));
  assign mem_fp_write_use_stall = if_id_q.valid && ex_mem_q.valid && ex_mem_q.fp_write && !ex_mem_q.mem_load &&
                                  ((if_id_uses_frs1 && (ex_mem_q.fp_rd_addr == if_id_frs1_addr)) ||
                                   (if_id_uses_frs2 && (ex_mem_q.fp_rd_addr == if_id_frs2_addr)) ||
                                   (if_id_uses_frs3 && (ex_mem_q.fp_rd_addr == if_id_frs3_addr)));

  // These conditions insert an ID/EX bubble while retaining IF/ID for replay.
  // They are distinct from redirect flushes: a redirect discards IF/ID, so an
  // ID prediction in that cycle is safely overridden by the older redirect.
  assign id_ex_replay_stall = load_use_stall | mem_load_use_stall |
                              fp_load_use_stall | mem_fp_load_use_stall |
                              fp_write_use_stall | mem_fp_write_use_stall;
  assign id_predict_enable = frontend_run_enable && backend_advance &&
                             !id_ex_replay_stall;

  // ---------------------------------------------------------------------------
  // FPU issue, completion, and integer-source forwarding
  // The adapter accepts one FP instruction while ID/EX is held. When its
  // result is available, EX emits the normal EX/MEM packet; FPR and fflags
  // therefore update only at the ordinary WB boundary.
  always_comb begin
    fp_gpr_operand_a = id_ex_q.rs1_data;
    if (ex_mem_q.valid && ex_mem_q.rd_we && !ex_mem_q.mem_load &&
        (ex_mem_q.rd_addr != 5'd0) && (ex_mem_q.rd_addr == id_ex_q.rs1_addr)) begin
      fp_gpr_operand_a = ex_mem_q.ex_result;
    end else if (wb_rd_we && (wb_rd_addr == id_ex_q.rs1_addr)) begin
      fp_gpr_operand_a = wb_rd_data;
    end
    fpu_issue = '0;
    fpu_issue.operand_a = id_ex_q.fp_rs1_data;
    fpu_issue.operand_b = id_ex_q.fp_rs2_data;
    fpu_issue.operand_c = id_ex_q.fp_rs3_data;
    if (id_ex_q.fp_operation == FP_OP_I2F) begin
      fpu_issue.operand_a = fp_gpr_operand_a;
    end else if (id_ex_q.fp_operation == FP_OP_SGNJ &&
                 (id_ex_q.instr[31:25] == 7'b1111000 ||
                  id_ex_q.instr[31:25] == 7'b1111001)) begin
      // FMV.W.X supplies a NaN-boxed FP32 operand to the RV64D CVFPU;
      // FMV.D.X transfers the XLEN-wide bit pattern unchanged.
      fpu_issue.operand_a = id_ex_q.fp_dst_fmt == FP_FMT_D ? fp_gpr_operand_a :
                            {32'hffff_ffff, fp_gpr_operand_a[31:0]};
      fpu_issue.operand_b = fpu_issue.operand_a;
    end
    // CVFPU implements ADD/SUB through its FMA datapath: it replaces operand
    // A with +1.0 and adds operands B and C.  Architectural rs1/rs2 must
    // therefore occupy B/C rather than the generic A/B positions.
    if (id_ex_q.fp_operation == FP_OP_ADD) begin
      fpu_issue.operand_b = id_ex_q.fp_rs1_data;
      fpu_issue.operand_c = id_ex_q.fp_rs2_data;
    end
    // FMV.X.W encodes rs2 as zero but uses the FP rs1 payload for both SGNJ
    // operands.  Keep B tied to the true source so the ordinary FPR bypass
    // updates it while the instruction is held behind a preceding FP writer.
    if (id_ex_q.fp_operation == FP_OP_SGNJ &&
        (id_ex_q.instr[31:25] == 7'b1110000 ||
         id_ex_q.instr[31:25] == 7'b1110001)) begin
      fpu_issue.operand_b = id_ex_q.fp_rs1_data;
    end
    fpu_issue.operation = id_ex_q.fp_operation;
    fpu_issue.operation_modifier = id_ex_q.fp_operation_modifier;
    fpu_issue.rounding_mode = id_ex_q.fp_rounding_dynamic ? fp_frm : id_ex_q.fp_rounding_mode;
    fpu_issue.src_fmt = id_ex_q.fp_src_fmt;
    fpu_issue.dst_fmt = id_ex_q.fp_dst_fmt;
    fpu_issue.int_fmt_d = id_ex_q.fp_int_fmt_d;
    fpu_issue.result_word = id_ex_q.fp_result_word;
    fpu_issue.write_gpr = !id_ex_q.fp_write;
    fpu_issue.rd_addr = id_ex_q.rd_addr;
    fpu_issue.tag = 8'h00;
  end
  assign fp_rm_invalid = id_ex_q.fp_op &&
                         ((id_ex_q.fp_rounding_dynamic ? fp_frm : id_ex_q.fp_rounding_mode) > 3'b100);
  assign fpu_issue_valid = id_ex_q.valid && id_ex_q.fp_op && !fp_fs_off && !fp_rm_invalid;
  assign fpu_complete_ready = backend_advance && id_ex_q.valid && id_ex_q.fp_op;
  assign fpu_wait = id_ex_q.valid && id_ex_q.fp_op && !fp_fs_off && !fp_rm_invalid && !fpu_complete_valid;

  fpu_adapter fpu_adapter_i (
    .clk              (clk),
    .rst_n            (rst_n),
    .issue_valid_i    (fpu_issue_valid),
    .issue_i          (fpu_issue),
    .issue_ready_o    (fpu_issue_ready),
    // An issued FP packet holds ID/EX until it completes, so no redirect or
    // replay flush can cancel it in flight.  Keep the generic adapter clear
    // input inactive here: coupling the global ID/EX flush into the CVFPU
    // control cone creates a non-architectural branch-to-FPU timing path.
    .flush_i          (1'b0),
    .complete_valid_o (fpu_complete_valid),
    .complete_o       (fpu_complete),
    .complete_ready_i (fpu_complete_ready),
    .busy_o           (fpu_busy)
  );

  // All redirects are merged in one place so IF sees a single next-PC decision.
  pipeline_control pipeline_control_i (
    // Pipeline activation
    .fetch_enable_i       (effective_fetch_enable),
    // Stall and configuration-barrier sources
    .imem_wait_i          (if_fetch_wait),
    .dmem_wait_i          (mem_wait),
    .muldiv_wait_i        (muldiv_wait),
    .fpu_wait_i           (fpu_wait),
    .load_use_stall_i     (id_ex_replay_stall),
    // Serialized EX control event
    .control_event_i      (ex_control_event),
    // Redirect sources, in frozen arbitration-priority order
    .trap_redirect_i      (trap_redirect),
    .trap_redirect_pc_i   (trap_redirect_pc),
    .debug_redirect_i     (debug_redirect | debug_resume_redirect),
    .debug_redirect_pc_i  (debug_resume_redirect ? debug_dpc : debug_redirect_pc),
    .fence_i_redirect_i   (fence_i_redirect),
    .fence_i_redirect_pc_i(fence_i_redirect_pc),
    .wfi_redirect_i       (wfi_redirect),
    .wfi_redirect_pc_i    (wfi_redirect_pc),
    .branch_redirect_i    (branch_redirect),
    .branch_redirect_pc_i (branch_redirect_pc),
    // Pipeline stage enables
    .pc_en_o              (pc_en),
    .if_id_en_o           (if_id_en),
    .backend_advance_o    (backend_advance),
    // Pipeline stage flushes
    .if_id_flush_o        (if_id_flush),
    .id_ex_flush_o        (id_ex_flush),
    .ex_mem_flush_o       (ex_mem_flush),
    // Resolved redirect to IF
    .redirect_valid_o     (redirect_valid),
    .redirect_pc_o        (redirect_pc)
  );

  // EX-side redirects retain priority. An ID prediction only takes effect when
  // no older redirect is present; id_predict_enable suppresses only replay
  // bubbles, not redirect flushes, because the mux and ID/EX flush below make
  // those predictions architecturally inert.
  assign fetch_redirect_valid = redirect_valid | id_predict_redirect;
  assign fetch_redirect_pc = redirect_valid ? redirect_pc : id_predict_redirect_pc;

  // ---------------------------------------------------------------------------
  // Five-stage data path: IF -> ID -> EX -> MEM -> WB
  // ---------------------------------------------------------------------------
  if_stage #(
    .ENABLE_UPPER_32_PREFETCH_P(ENABLE_UPPER_32_PREFETCH_P)
  ) if_stage_i (
    // Clock and reset
    .clk                  (clk),
    .rst_n                (rst_n),
    // Fetch activation and sequential PC control
    .fetch_enable_i       (effective_fetch_enable),
    .boot_addr_i          (boot_addr_i),
    .pc_en_i              (pc_en),
    // Redirect control
    .redirect_valid_i     (fetch_redirect_valid),
    .redirect_pc_i        (fetch_redirect_pc),
    // I-bus transaction (IF <-> SoC)
    .imem_ready_i         (imem_ready_i),
    .imem_rvalid_i        (imem_rvalid_i),
    .imem_rdata_i         (imem_rdata_i),
    .imem_req_o           (imem_req_o),
    .imem_addr_o          (if_imem_addr),
    // IF/ID boundary
    .if_id_en_i           (if_id_en),
    .if_id_flush_i        (if_id_flush),
    .if_id_o              (if_id_q),
    // Fetch status and Debug halt-PC observation
    .fetch_wait_o         (if_fetch_wait),
    .halt_pc_o            (if_halt_pc)
  );

  id_stage #(
    .ENABLE_BHT_P(ENABLE_BHT_P),
    .ENABLE_RAS_P(ENABLE_RAS_P)
  ) id_stage_i (
    // Clock and reset
    .clk                  (clk),
    .rst_n                (rst_n),
    // IF/ID -> ID/EX pipeline boundary
    .if_id_i              (if_id_q),
    .id_ex_en_i           (backend_advance),
    .id_ex_flush_i        (id_ex_flush),
    .id_ex_o              (id_ex_q),
    // WB register-file writeback
    .wb_we_i              (wb_rd_we),
    .wb_rd_addr_i         (wb_rd_addr),
    .wb_rd_data_i         (wb_rd_data),
    // Debug GPR access
    .dbg_gpr_raddr_i      (debug_reg_addr_i[4:0]),
    .dbg_gpr_rdata_o      (debug_gpr_rdata),
    .dbg_gpr_waddr_i      (debug_reg_addr_i[4:0]),
    .dbg_gpr_wdata_i      (debug_reg_wdata_i),
    .dbg_gpr_we_i         (debug_gpr_write),

    // FPR writeback and Debug FPR access
    .fp_wb_we_i           (fp_wb_we),
    .fp_wb_rd_addr_i      (fp_wb_rd_addr),
    .fp_wb_data_i         (fp_wb_data),
    .dbg_fpr_raddr_i      (debug_reg_addr_i[4:0]),
    .dbg_fpr_rdata_o      (debug_fpr_rdata),
    .dbg_fpr_waddr_i      (debug_reg_addr_i[4:0]),
    .dbg_fpr_wdata_i      (debug_reg_wdata_i),
    .dbg_fpr_we_i         (debug_fpr_write),

    // Decode source-register metadata
    .src_rs1_addr_o       (if_id_rs1_addr),
    .src_rs2_addr_o       (if_id_rs2_addr),
    .uses_rs1_o           (if_id_uses_rs1),
    .uses_rs2_o           (if_id_uses_rs2),
    .conditional_branch_o (if_id_conditional_branch),
    .store_instruction_o  (if_id_store_instruction),
    .uses_frs1_o          (if_id_uses_frs1),
    .uses_frs2_o          (if_id_uses_frs2),
    .uses_frs3_o          (if_id_uses_frs3),
    .src_frs1_addr_o      (if_id_frs1_addr),
    .src_frs2_addr_o      (if_id_frs2_addr),
    .src_frs3_addr_o      (if_id_frs3_addr),

    // BHT training from resolved EX branches
    .bht_update_valid_i   (bht_update_valid),
    .bht_update_pc_i      (bht_update_pc),
    .bht_update_taken_i   (bht_update_taken),
    // RAS maintenance from resolved EX control transfers
    .ras_push_valid_i     (ras_push_valid),
    .ras_push_addr_i      (ras_push_addr),
    .ras_pop_valid_i      (ras_pop_valid),
    // ID-stage direct-control prediction
    .early_redirect_enable_i(id_predict_enable),
    .predict_redirect_o   (id_predict_redirect),
    .predict_redirect_pc_o(id_predict_redirect_pc)
  );

  ex_stage #(
    .RESET_VECTOR_ADDR_P(RESET_VECTOR_ADDR_P),
    .DEBUG_BASE_ADDR_P  (DEBUG_BASE_ADDR_P),
    .MUL_ITER_BITS_P    (MUL_ITER_BITS_P)
  ) ex_stage_i (
    // Clock and reset
    .clk                  (clk),
    .rst_n                (rst_n),
    // Pipeline packets and EX/MEM boundary
    .id_ex_i              (id_ex_q),
    .ex_mem_fwd_i         (ex_mem_q),
    .mem_wb_fwd_i         (mem_wb_q),
    .load_result_bypass_valid_i(load_response_bypass_valid),
    .load_result_bypass_rd_addr_i(load_result_bypass_rd_addr),
    .load_result_bypass_data_i(load_result_bypass_data),
    .ex_mem_en_i          (backend_advance),
    .ex_mem_flush_i       (ex_mem_flush),
    .ex_mem_o             (ex_mem_q),
    // Platform event inputs
    .irq_i                (irq_i),
    .mtime_i              (mtime_i),
    // Retired control event from WB
    .control_trap_enter_i (control_trap_enter),
    .control_trap_return_i(control_trap_return),
    .control_debug_enter_i(control_debug_enter),
    .control_trap_pc_i    (control_trap_pc),
    .control_trap_cause_i (control_trap_cause),
    .control_trap_value_i (control_trap_value),
    .control_debug_dpc_i  (control_debug_dpc),
    .control_debug_cause_i(control_debug_cause),
    // Debug run control and abstract CSR access
    .debug_mode_i         (debug_mode_q),
    .debug_external_enter_i(debug_external_enter),
    .debug_resume_i       (debug_resume_redirect),
    .debug_external_dpc_i (if_halt_pc),
    .debug_csr_req_i      (debug_csr_access),
    .debug_csr_write_i    (debug_reg_write_i),
    .debug_csr_addr_i     (debug_reg_addr_i[11:0]),
    .debug_csr_wdata_i    (debug_reg_wdata_i),
    .debug_csr_rdata_o    (debug_csr_rdata),
    .debug_csr_error_o    (debug_csr_error),
    // HPM and FPU retirement observations. Keep HPM's load-use qualifier aligned
    // with pipeline control. A
    // dependent instruction can be stalled with the load in either ID/EX or
    // EX/MEM; omitting the latter under-counts the documented event.
    .hpm_load_use_stall_i (load_use_stall | mem_load_use_stall | fp_load_use_stall | mem_fp_load_use_stall),
    .hpm_ifetch_wait_i    (if_fetch_wait),
    .hpm_dmem_stall_i     (mem_wait),
    .hpm_wfi_wait_i       (wfi_sleep_q),
    .fpu_complete_valid_i (fpu_complete_valid),
    .fpu_complete_i       (fpu_complete),
    .fp_commit_i          (fp_wb_dirty),
    .fp_dirty_i           (fp_wb_dirty),
    .fp_fflags_i          (fp_wb_fflags),

    // Redirect and Debug-entry results
    .branch_redirect_o    (branch_redirect),
    .branch_redirect_pc_o (branch_redirect_pc),
    .trap_redirect_o      (trap_redirect),
    .trap_redirect_pc_o   (trap_redirect_pc),
    .debug_redirect_o     (debug_redirect),
    .debug_redirect_pc_o  (debug_redirect_pc),
    .debug_dpc_o          (debug_dpc),
    .debug_cause_o        (debug_cause),
    // BHT training from resolved conditional branches
    .bht_update_valid_o   (bht_update_valid),
    .bht_update_pc_o      (bht_update_pc),
    .bht_update_taken_o   (bht_update_taken),
    // RAS maintenance for ID-stage return prediction
    .ras_push_valid_o     (ras_push_valid),
    .ras_push_addr_o      (ras_push_addr),
    .ras_pop_valid_o      (ras_pop_valid),
    .control_event_o      (ex_control_event),
    .wfi_redirect_o       (wfi_redirect),
    .muldiv_wait_o        (muldiv_wait),
    .fp_frm_o             (fp_frm),
    .fp_fs_off_o          (fp_fs_off),
    // Optional local-memory read handshake
    .lmem_accept_i        (lmem_accept),
    .lmem_req_o           (lmem_req_internal),
    .lmem_addr_o          (lmem_addr_internal)
  );

  mem_stage mem_stage_i (
    // Clock and reset
    .clk                  (clk),
    .rst_n                (rst_n),
    // EX/MEM -> MEM/WB pipeline boundary
    .ex_mem_i             (ex_mem_q),
    .mem_wb_fwd_i         (mem_wb_q),
    .ex_mem_en_i          (backend_advance),
    // Normal D-bus transaction (MEM <-> SoC)
    .data_req_ready_i     (1'b1),
    .data_resp_valid_i    (data_resp_valid_i),
    .data_rdata_i         (data_rdata_i),
    .data_err_i           (data_err_i),
    .data_fence_o         (data_fence_o),
    .data_fence_done_i    (data_fence_done_i),
    .data_fence_err_i     (data_fence_err_i),
    .data_req_o           (data_req_o),
    .data_addr_o          (data_addr_o),
    .data_wdata_o         (data_wdata_o),
    .data_we_o            (data_we_o),
    .data_be_o            (data_be_o),
    .data_atomic_op_o     (data_atomic_op_o),
    .data_atomic_aq_o     (data_atomic_aq_o),
    .data_atomic_rl_o     (data_atomic_rl_o),
    // Optional local-memory read completion (SoC -> MEM)
    .lmem_resp_valid_i    (lmem_resp_valid),
    .lmem_rdata_i         (lmem_rdata),
    .lmem_err_i           (lmem_err),
    .lmem_response_o      (mem_lmem_response),
    .load_result_bypass_valid_o(load_result_bypass_valid),
    .load_result_bypass_rd_addr_o(load_result_bypass_rd_addr),
    .load_result_bypass_data_o(load_result_bypass_data),
    // MEM pipeline completion
    .mem_wait_o           (mem_wait),
    .mem_wb_o             (mem_wb_q)
  );

  wb_stage wb_stage_i (
    // MEM/WB pipeline packet
    .mem_wb_i             (mem_wb_q),
    // Architectural GPR writeback
    .rd_addr_o            (wb_rd_addr),
    .rd_data_o            (wb_rd_data),
    .rd_we_o              (wb_rd_we),

    // FPR writeback and FCSR commit
    .fp_we_o              (fp_wb_we),
    .fp_rd_addr_o         (fp_wb_rd_addr),
    .fp_rd_data_o         (fp_wb_data),
    .fp_fflags_o          (fp_wb_fflags),
    .fp_dirty_o           (fp_wb_dirty),

    // Committed architectural control actions
    .control_commit_o     (control_commit),
    .control_trap_enter_o (control_trap_enter),
    .control_trap_return_o(control_trap_return),
    .control_debug_enter_o(control_debug_enter),
    .control_debug_return_o(control_debug_return),
    .control_wfi_o        (control_wfi),
    .control_trap_pc_o    (control_trap_pc),
    .control_trap_cause_o (control_trap_cause),
    .control_trap_value_o (control_trap_value),
    .control_debug_dpc_o  (control_debug_dpc),
    .control_debug_cause_o(control_debug_cause)
  );

  // ---------------------------------------------------------------------------
  // Top-level observations
  // The D-bus connects directly to MEM. IF owns I-bus request bookkeeping.
  // ---------------------------------------------------------------------------
  assign imem_addr_o        = if_imem_addr;

  assign debug_halted_o    = debug_halted_q;
  assign debug_running_o   = !debug_halted_q;
  assign debug_pc_o        = debug_dpc;
  assign debug_cause_o     = debug_cause;

endmodule
