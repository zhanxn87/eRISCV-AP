// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// RV64 M/S/U CSR block with Sv39 SATP architectural state.
import riscv_pkg::*;

module csr_file #(
  parameter xlen_t RESET_VECTOR_ADDR_P = xlen_t'(RESET_VECTOR_ADDR)
) (
  // Clock and reset
  input  logic        clk,
  input  logic        rst_n,

  // Executing CSR instruction transaction
  input  logic        csr_access_i,
  input  logic [1:0]  csr_op_i,
  input  logic [11:0] csr_addr_i,
  input  logic        csr_write_intent_i,
  input  xlen_t       csr_wdata_i,
  output xlen_t       csr_rdata_o,
  output logic        csr_illegal_access_o,

  // Trap entry and return
  input  logic        trap_enter_i,
  input  xlen_t       trap_pc_i,
  input  xlen_t       trap_cause_i,
  input  xlen_t       trap_value_i,
  input  logic        trap_return_i,
  input  logic        trap_sret_i,

  // Debug entry and run state
  input  logic        debug_enter_i,
  input  xlen_t       debug_dpc_i,
  input  logic [2:0]  debug_cause_i,
  input  logic        debug_mode_i,

  // Retirement, time, interrupt, and HPM event observations
  input  logic        retire_i,
  input  logic [1:0]  instret_pending_i,
  input  logic [31:0] irq_i,
  input  logic [63:0] mtime_i,
  input  logic [HPM_EVENT_COUNT-1:0] hpm_event_i,

  // FPU architectural retirement. fp_commit_i qualifies fflags accumulation;
  // fp_dirty_i controls the mstatus.FS transition to Dirty.
  input  logic        fp_commit_i,
  input  logic        fp_dirty_i,
  input  logic [4:0]  fp_fflags_i,
  output logic [2:0]  frm_o,
  output logic        fs_off_o,

  // Debug abstract CSR transaction
  input  logic        debug_csr_req_i,
  input  logic        debug_csr_write_i,
  input  logic [11:0] debug_csr_addr_i,
  input  xlen_t       debug_csr_wdata_i,
  output xlen_t       debug_csr_rdata_o,
  output logic        debug_csr_error_o,

  // Trigger retirement observation and state views
  input  logic        trigger_retire_i,
  output xlen_t       trigger_mcontrol_o,
  output xlen_t       trigger_tdata2_o,
  output xlen_t       trigger_icount_o,

  // Architectural trap and Debug state views
  output xlen_t       mtvec_o,
  output xlen_t       mepc_o,
  output xlen_t       stvec_o,
  output xlen_t       sepc_o,
  output xlen_t       medeleg_o,
  output xlen_t       dpc_o,
  output logic        dcsr_step_o,
  output logic        dcsr_ebreakm_o,
  output logic [2:0]  dcsr_cause_o,

  // Interrupt arbitration result
  output logic        interrupt_ready_o,
  output logic        interrupt_to_s_o,
  output xlen_t       interrupt_cause_o,

  // Current privilege policy
  output privilege_mode_e privilege_mode_o,
  output logic            mstatus_tsr_o,
  output logic            mstatus_tw_o,
  output logic            mstatus_mprv_o,
  output privilege_mode_e mstatus_mpp_o,
  output logic            mstatus_tvm_o,
  output logic            mstatus_sum_o,
  output logic            mstatus_mxr_o,
  output xlen_t           satp_o
);

  localparam int HPM_EVENT_INDEX_W = (HPM_EVENT_COUNT > 1) ? $clog2(HPM_EVENT_COUNT) : 1;
  localparam logic [7:0] HPM_EVENT_COUNT_U8 = HPM_EVENT_COUNT[7:0];

  // ---------------------------------------------------------------------------
  // Architectural M/S/U state
  // ---------------------------------------------------------------------------
  xlen_t       mstatus_q;
  logic [4:0]  fflags_q;
  logic [2:0]  frm_q;
  xlen_t       mie_q;
  xlen_t       mip_sw_q;
  xlen_t       sip_sw_q;
  xlen_t       medeleg_q;
  xlen_t       mideleg_q;
  xlen_t       mtvec_q;
  xlen_t       stvec_q;
  xlen_t       scounteren_q;
  xlen_t       mscratch_q;
  xlen_t       mepc_q;
  xlen_t       mcause_q;
  xlen_t       mtval_q;
  xlen_t       sscratch_q;
  xlen_t       sepc_q;
  xlen_t       scause_q;
  xlen_t       stval_q;
  xlen_t       satp_q;
  xlen_t       mcountinhibit_q;
  xlen_t       mcounteren_q;
  privilege_mode_e privilege_mode_q;

  // ---------------------------------------------------------------------------
  // Counters and HPM state
  // ---------------------------------------------------------------------------
  xlen_t       mcycle_q;
  xlen_t       minstret_q;
  xlen_t       mhpmcounter3_q;
  xlen_t       mhpmcounter4_q;
  xlen_t       mhpmcounter5_q;
  xlen_t       mhpmcounter6_q;
  logic [7:0]  mhpmevent3_q;
  logic [7:0]  mhpmevent4_q;
  logic [7:0]  mhpmevent5_q;
  logic [7:0]  mhpmevent6_q;
  // Sample the event/configuration decision at the observation boundary and
  // update the counters in the following cycle. This keeps EX event logic
  // out of the HPM counter increment path without losing back-to-back events.
  logic [3:0]  hpm_increment_q;

  // ---------------------------------------------------------------------------
  // Debug and trigger state
  // ---------------------------------------------------------------------------
  logic        dcsr_step_q;
  logic        dcsr_ebreakm_q;
  logic [2:0]  dcsr_cause_q;
  xlen_t       dpc_q;
  xlen_t       dscratch0_q;
  xlen_t       dscratch1_q;
  logic        tselect_q;
  xlen_t       mcontrol_q;
  xlen_t       mcontrol_tdata2_q;
  xlen_t       icount_q;

  // Combinational CSR views and access qualification
  xlen_t       mip_value;
  xlen_t       sstatus_value;
  xlen_t       sie_value;
  xlen_t       sip_value;
  xlen_t       dcsr_value;
  xlen_t       csr_wvalue;
  logic        meip_pending;
  logic        msip_pending;
  logic        mtip_pending;
  logic        seip_pending;
  logic        ssip_pending;
  logic        stip_pending;
  logic        machine_interrupt_ready;
  logic        supervisor_interrupt_ready;
  logic        csr_known;
  logic        csr_write_legal;
  logic        csr_insufficient_privilege;
  logic        csr_counter_access;
  logic        csr_counter_access_required;
  logic        csr_tvm_violation;
  privilege_mode_e csr_min_privilege;
  logic [3:0]  hpm_counter_write;
  logic        trap_delegated_to_s;

  // ---------------------------------------------------------------------------
  // CSR access state
  // ---------------------------------------------------------------------------
  logic        csr_unimplemented_user_hpm;
  xlen_t       csr_counteren_mask;

  // ---------------------------------------------------------------------------
  // CSR write sanitizers and access helpers
  // ---------------------------------------------------------------------------
  function automatic xlen_t sanitize_mstatus(input xlen_t value);
    xlen_t sanitized;
    begin
      sanitized = '0;
      sanitized[1:0]   = value[1:0];     // SIE and reserved bit 0
      sanitized[3]     = value[3];       // MIE
      sanitized[6:4]   = value[6:4];     // SPIE plus WPRI bits retained for compatibility
      sanitized[7]     = value[7];       // MPIE
      sanitized[8]     = value[8];       // SPP
      sanitized[10:9]  = value[10:9];    // VS
      if (HAS_SMODE) begin
        unique case (value[12:11])
          PRIV_U,
          PRIV_S,
          PRIV_M: sanitized[12:11] = value[12:11];
          default: sanitized[12:11] = PRIV_M;
        endcase
      end else if (HAS_UMODE) begin
        unique case (value[12:11])
          PRIV_U,
          PRIV_M: sanitized[12:11] = value[12:11];
          default: sanitized[12:11] = PRIV_M;
        endcase
      end else begin
        sanitized[12:11] = PRIV_M;
      end
      sanitized[14:13] = value[14:13];   // FS
      sanitized[16:15] = value[16:15];   // XS
      sanitized[22:18] = value[22:18];   // TSR,TW,TVM,MXR,SUM
      sanitized[17]    = HAS_MPRV && value[17]; // MPRV
      if (HAS_UMODE)
        sanitized[33:32] = 2'b10;         // UXL = RV64
      if (HAS_SMODE)
        sanitized[35:34] = 2'b10;         // SXL = RV64
      sanitized[CORE_XLEN-1] = (sanitized[14:13] == 2'b11) ||
                               (sanitized[16:15] == 2'b11) ||
                               (sanitized[10:9]  == 2'b11);
      sanitize_mstatus = sanitized;
    end
  endfunction

  function automatic xlen_t sanitize_mie(input xlen_t value);
    sanitize_mie = value & xlen_t'(32'h0000_0aaa);
  endfunction

  function automatic xlen_t sanitize_mip(input xlen_t value);
    sanitize_mip = value & xlen_t'(32'h0000_0008);
  endfunction

  function automatic xlen_t sanitize_sip(input xlen_t value);
    sanitize_sip = value & xlen_t'(32'h0000_0002);
  endfunction

  function automatic xlen_t sanitize_medeleg(input xlen_t value);
    sanitize_medeleg = value & xlen_t'(32'h0000_01ff);
  endfunction

  function automatic xlen_t sanitize_mideleg(input xlen_t value);
    sanitize_mideleg = value & xlen_t'(32'h0000_0222);
  endfunction

  function automatic xlen_t sanitize_mtvec(input xlen_t value);
    sanitize_mtvec = {value[CORE_XLEN-1:2], 1'b0, (value[1:0] == 2'b01)};
  endfunction

  function automatic xlen_t sanitize_mepc(input xlen_t value);
    sanitize_mepc = value & ~xlen_t'(1);
  endfunction

  function automatic xlen_t sanitize_satp(input xlen_t current,
                                           input xlen_t value);
    xlen_t sanitized;
    begin
      // Unsupported MODE writes leave the CSR unchanged, as required by satp.
      unique case (value[63:60])
        4'd0,
        4'd8: begin
          sanitized = value;
          // AP uses a 48-bit physical address, so only PPN[35:0] is usable.
          sanitized[43:36] = '0;
        end
        default: sanitized = current;
      endcase
      sanitize_satp = sanitized;
    end
  endfunction

  function automatic xlen_t write_sstatus(input xlen_t mstatus,
                                          input xlen_t value);
    xlen_t merged;
    begin
      merged = mstatus;
      merged[1] = value[1];
      merged[5] = value[5];
      merged[8] = value[8];
      merged[10:9] = value[10:9];
      merged[14:13] = value[14:13];
      merged[16:15] = value[16:15];
      merged[19:18] = value[19:18];
      write_sstatus = sanitize_mstatus(merged);
    end
  endfunction

  function automatic logic [7:0] sanitize_hpm_event(input xlen_t value);
    unique case (value[7:0])
      HPM_EVENT_NONE,
      HPM_EVENT_BRANCH_RETIRED,
      HPM_EVENT_BRANCH_TAKEN,
      HPM_EVENT_CONTROL_TRANSFER_RETIRED,
      HPM_EVENT_EXCEPTION_TAKEN,
      HPM_EVENT_INTERRUPT_TAKEN,
      HPM_EVENT_IFETCH_WAIT_CYCLES,
      HPM_EVENT_DATA_WAIT_CYCLES,
      HPM_EVENT_PIPELINE_STALL_CYCLES,
      HPM_EVENT_LOAD_USE_STALL_CYCLES,
      HPM_EVENT_WFI_CYCLES,
      HPM_EVENT_DEBUG_ENTRY,
      HPM_EVENT_IRQ_PENDING_CYCLES: sanitize_hpm_event = value[7:0];
      default: sanitize_hpm_event = HPM_EVENT_NONE;
    endcase
  endfunction

  function automatic xlen_t counteren_mask_for_csr(input logic [11:0] addr);
    begin
      unique case (addr)
        CSR_CYCLE:        counteren_mask_for_csr = xlen_t'(32'h0000_0001);
        CSR_TIME:         counteren_mask_for_csr = xlen_t'(32'h0000_0002);
        CSR_INSTRET:      counteren_mask_for_csr = xlen_t'(32'h0000_0004);
        CSR_HPMCOUNTER3:  counteren_mask_for_csr = xlen_t'(32'h0000_0008);
        CSR_HPMCOUNTER4:  counteren_mask_for_csr = xlen_t'(32'h0000_0010);
        CSR_HPMCOUNTER5:  counteren_mask_for_csr = xlen_t'(32'h0000_0020);
        CSR_HPMCOUNTER6:  counteren_mask_for_csr = xlen_t'(32'h0000_0040);
        default:          counteren_mask_for_csr = '0;
      endcase
    end
  endfunction

  function automatic logic hpm_event_active(input logic [7:0] event_id);
    if (event_id < HPM_EVENT_COUNT_U8) begin
      hpm_event_active = hpm_event_i[event_id[HPM_EVENT_INDEX_W-1:0]];
    end else begin
      hpm_event_active = 1'b0;
    end
  endfunction

  always_comb begin
    hpm_counter_write = 4'b0000;
    if (csr_access_i && !csr_illegal_access_o && csr_write_intent_i) begin
      unique case (csr_addr_i)
        CSR_MHPMCOUNTER3: hpm_counter_write[0] = 1'b1;
        CSR_MHPMCOUNTER4: hpm_counter_write[1] = 1'b1;
        CSR_MHPMCOUNTER5: hpm_counter_write[2] = 1'b1;
        CSR_MHPMCOUNTER6: hpm_counter_write[3] = 1'b1;
        default: begin
        end
      endcase
    end
  end

  // --- Interrupt pending, delegation, and prioritisation ---
  //
  // Existing platform sources use machine positions 11/7/3. For the S-mode
  // baseline they are also mirrored to SEIP/STIP/SSIP; a future CLINT/PLIC can
  // instead drive the supervisor positions directly. M-level sources retain
  // priority whenever both classes are enabled.
  always_comb begin
    mip_value = '0;
    mip_value[11] = irq_i[11];
    mip_value[9]  = irq_i[9];
    mip_value[7]  = irq_i[7];
    mip_value[5]  = irq_i[5] | irq_i[7];
    mip_value[3]  = irq_i[3] | mip_sw_q[3];
    mip_value[1]  = irq_i[1] | irq_i[3] | sip_sw_q[1];
  end
  assign meip_pending = mip_value[11] & mie_q[11];
  assign msip_pending = mip_value[3] & mie_q[3];
  assign mtip_pending = mip_value[7] & mie_q[7];
  assign seip_pending = mip_value[9] & mie_q[9] & mideleg_q[9];
  assign ssip_pending = mip_value[1] & mie_q[1] & mideleg_q[1];
  assign stip_pending = mip_value[5] & mie_q[5] & mideleg_q[5];

  assign machine_interrupt_ready = ((privilege_mode_q != PRIV_M) || mstatus_q[3]) &&
                                   (meip_pending | msip_pending | mtip_pending);
  assign supervisor_interrupt_ready = (privilege_mode_q != PRIV_M) &&
                                      ((privilege_mode_q == PRIV_U) || mstatus_q[1]) &&
                                      (seip_pending | ssip_pending | stip_pending);
  assign interrupt_ready_o = machine_interrupt_ready | supervisor_interrupt_ready;
  assign interrupt_to_s_o = !machine_interrupt_ready && supervisor_interrupt_ready;
  assign trap_delegated_to_s = (privilege_mode_q != PRIV_M) &&
                               ((trap_cause_i[CORE_XLEN-1] &&
                                 mideleg_q[trap_cause_i[5:0]]) ||
                                (!trap_cause_i[CORE_XLEN-1] &&
                                 medeleg_q[trap_cause_i[5:0]]));

  always_comb begin
    if (machine_interrupt_ready) begin
      if (meip_pending)
        interrupt_cause_o = (xlen_t'(1) << (CORE_XLEN-1)) | xlen_t'(11);
      else if (msip_pending)
        interrupt_cause_o = (xlen_t'(1) << (CORE_XLEN-1)) | xlen_t'(3);
      else
        interrupt_cause_o = (xlen_t'(1) << (CORE_XLEN-1)) | xlen_t'(7);
    end else if (seip_pending) begin
      interrupt_cause_o = (xlen_t'(1) << (CORE_XLEN-1)) | xlen_t'(9);
    end else if (ssip_pending) begin
      interrupt_cause_o = (xlen_t'(1) << (CORE_XLEN-1)) | xlen_t'(1);
    end else begin
      interrupt_cause_o = (xlen_t'(1) << (CORE_XLEN-1)) | xlen_t'(5);
    end
  end

  // ---------------------------------------------------------------------------
  // CSR instruction access legality
  // ---------------------------------------------------------------------------
  assign csr_unimplemented_user_hpm =
      ((csr_addr_i >= 12'hc07) && (csr_addr_i <= 12'hc1f));

  always_comb begin
    csr_known = 1'b1;
    csr_write_legal = 1'b1;
    csr_counteren_mask = counteren_mask_for_csr(csr_addr_i);
    csr_min_privilege = privilege_mode_e'(csr_addr_i[9:8]);
    csr_insufficient_privilege = privilege_mode_q < csr_min_privilege;
    csr_counter_access_required = (csr_counteren_mask != '0) ||
                                  csr_unimplemented_user_hpm;
    csr_tvm_violation = (csr_addr_i == CSR_SATP) &&
                        (privilege_mode_q == PRIV_S) && mstatus_q[20];
    csr_counter_access = (privilege_mode_q == PRIV_M) ||
                         (HAS_MCOUNTEREN && ((mcounteren_q & csr_counteren_mask) != '0) &&
                          ((privilege_mode_q == PRIV_S) ||
                           ((privilege_mode_q == PRIV_U) &&
                            ((scounteren_q & csr_counteren_mask) != '0))));
    if (csr_unimplemented_user_hpm) begin
      csr_write_legal = !csr_write_intent_i;
    end else begin
      unique case (csr_addr_i)
        CSR_FFLAGS,
        CSR_FRM,
        CSR_FCSR,
        CSR_SSTATUS,
        CSR_SIE,
        CSR_STVEC,
        CSR_SCOUNTEREN,
        CSR_SSCRATCH,
        CSR_SEPC,
        CSR_SCAUSE,
        CSR_STVAL,
        CSR_SIP,
        CSR_SATP,
        CSR_MSTATUS,
        CSR_MIE,
        CSR_MTVEC,
        CSR_MSCRATCH,
        CSR_MEPC,
        CSR_MCAUSE,
        CSR_MTVAL,
        CSR_MIP,
        CSR_MCOUNTINHIBIT,
        CSR_MCOUNTEREN,
        CSR_MEDELEG,
        CSR_MIDELEG,
        CSR_MCYCLE,
        CSR_MINSTRET,
        CSR_MHPMCOUNTER3,
        CSR_MHPMCOUNTER4,
        CSR_MHPMCOUNTER5,
        CSR_MHPMCOUNTER6,
        CSR_MHPMEVENT3,
        CSR_MHPMEVENT4,
        CSR_MHPMEVENT5,
        CSR_MHPMEVENT6: begin
        end
        CSR_MISA,
        CSR_CYCLE,
        CSR_TIME,
        CSR_INSTRET,
        CSR_HPMCOUNTER3,
        CSR_HPMCOUNTER4,
        CSR_HPMCOUNTER5,
        CSR_HPMCOUNTER6,
        CSR_MHARTID: begin
          csr_write_legal = !csr_write_intent_i;
        end
        CSR_DCSR,
        CSR_DPC,
        CSR_DSCRATCH0,
        CSR_DSCRATCH1,
        CSR_TSELECT,
        CSR_TDATA1,
        CSR_TDATA2: begin
        end
        default: begin
          csr_known = 1'b0;
          csr_write_legal = 1'b0;
        end
      endcase
    end
    if ((csr_addr_i == CSR_MCOUNTEREN) && !HAS_MCOUNTEREN) begin
      csr_known = 1'b0;
      csr_write_legal = 1'b0;
    end
  end

  assign csr_illegal_access_o = csr_access_i &&
                                (!csr_known || !csr_write_legal || csr_tvm_violation ||
                                 (csr_counter_access_required && !csr_counter_access) ||
                                 (!csr_counter_access_required && csr_insufficient_privilege));

  // ---------------------------------------------------------------------------
  // Architectural CSR read data and instruction write value
  // ---------------------------------------------------------------------------
  always_comb begin
    sstatus_value = '0;
    sstatus_value[CORE_XLEN-1] = mstatus_q[CORE_XLEN-1];
    if (HAS_UMODE)
      sstatus_value[33:32] = mstatus_q[33:32];
    sstatus_value[19:18] = mstatus_q[19:18];
    sstatus_value[16:15] = mstatus_q[16:15];
    sstatus_value[14:13] = mstatus_q[14:13];
    sstatus_value[10:9] = mstatus_q[10:9];
    sstatus_value[8] = mstatus_q[8];
    sstatus_value[5] = mstatus_q[5];
    sstatus_value[1] = mstatus_q[1];
    sie_value = mie_q & mideleg_q;
    sip_value = mip_value & mideleg_q;
  end

  always_comb begin
    dcsr_value = '0;
    dcsr_value[31:28] = 4'h4;
    dcsr_value[15]    = dcsr_ebreakm_q;
    dcsr_value[8:6]   = dcsr_cause_q;
    dcsr_value[2]     = dcsr_step_q;
    dcsr_value[1:0]   = 2'b11;
  end

  always_comb begin
    csr_rdata_o = '0;
    if (csr_unimplemented_user_hpm) begin
      csr_rdata_o = '0;
    end else begin
      // Common Machine/debug CSR map.
      unique case (csr_addr_i)
      CSR_FFLAGS:       csr_rdata_o = xlen_t'(fflags_q);
      CSR_FRM:          csr_rdata_o = xlen_t'(frm_q);
      CSR_FCSR:         csr_rdata_o = xlen_t'({frm_q, fflags_q});
      CSR_SSTATUS:      csr_rdata_o = sstatus_value;
      CSR_SIE:          csr_rdata_o = sie_value;
      CSR_STVEC:        csr_rdata_o = stvec_q;
      CSR_SCOUNTEREN:   csr_rdata_o = scounteren_q;
      CSR_SSCRATCH:     csr_rdata_o = sscratch_q;
      CSR_SEPC:         csr_rdata_o = sepc_q;
      CSR_SCAUSE:       csr_rdata_o = scause_q;
      CSR_STVAL:        csr_rdata_o = stval_q;
      CSR_SIP:          csr_rdata_o = sip_value;
      CSR_SATP:         csr_rdata_o = satp_q;
      CSR_MSTATUS:      csr_rdata_o = mstatus_q;
      CSR_MISA:         csr_rdata_o = (xlen_t'(2) << (CORE_XLEN-2)) |
                                      xlen_t'(32'h0000_1105) |
                                      (HAS_B_EXT ? xlen_t'(32'h0000_0002) : '0) |
                                      (HAS_D_EXT ? xlen_t'(32'h0000_0008) : '0) |
                                      (HAS_F_EXT ? xlen_t'(32'h0000_0020) : '0) |
                                      (HAS_SMODE ? xlen_t'(32'h0004_0000) : '0) |
                                      (HAS_UMODE ? xlen_t'(32'h0010_0000) : '0);
      CSR_MIE:          csr_rdata_o = mie_q;
      CSR_MTVEC:        csr_rdata_o = mtvec_q;
      CSR_MSCRATCH:     csr_rdata_o = mscratch_q;
      CSR_MEPC:         csr_rdata_o = mepc_q;
      CSR_MCAUSE:       csr_rdata_o = mcause_q;
      CSR_MTVAL:        csr_rdata_o = mtval_q;
      CSR_MIP:          csr_rdata_o = mip_value;
      CSR_MEDELEG:      csr_rdata_o = medeleg_q;
      CSR_MIDELEG:      csr_rdata_o = mideleg_q;
      CSR_MCOUNTINHIBIT: csr_rdata_o = mcountinhibit_q;
      CSR_MCOUNTEREN:    csr_rdata_o = HAS_MCOUNTEREN ? mcounteren_q : '0;
      CSR_MHARTID:      csr_rdata_o = '0;
      CSR_MCYCLE,
      CSR_CYCLE:        csr_rdata_o = mcycle_q;
      CSR_TIME:         csr_rdata_o = xlen_t'(mtime_i);
      CSR_MINSTRET,
      CSR_INSTRET:      csr_rdata_o = minstret_q + xlen_t'(instret_pending_i);
      CSR_MHPMCOUNTER3,
      CSR_HPMCOUNTER3:  csr_rdata_o = mhpmcounter3_q;
      CSR_MHPMCOUNTER4,
      CSR_HPMCOUNTER4:  csr_rdata_o = mhpmcounter4_q;
      CSR_MHPMCOUNTER5,
      CSR_HPMCOUNTER5:  csr_rdata_o = mhpmcounter5_q;
      CSR_MHPMCOUNTER6,
      CSR_HPMCOUNTER6:  csr_rdata_o = mhpmcounter6_q;
      CSR_MHPMEVENT3:   csr_rdata_o = xlen_t'(mhpmevent3_q);
      CSR_MHPMEVENT4:   csr_rdata_o = xlen_t'(mhpmevent4_q);
      CSR_MHPMEVENT5:   csr_rdata_o = xlen_t'(mhpmevent5_q);
      CSR_MHPMEVENT6:   csr_rdata_o = xlen_t'(mhpmevent6_q);
      CSR_DCSR:         csr_rdata_o = dcsr_value;
      CSR_DPC:          csr_rdata_o = dpc_q;
      CSR_DSCRATCH0:    csr_rdata_o = dscratch0_q;
      CSR_DSCRATCH1:    csr_rdata_o = dscratch1_q;
      CSR_TSELECT:      csr_rdata_o = xlen_t'(tselect_q);
      CSR_TDATA1:       csr_rdata_o = tselect_q ? icount_q : mcontrol_q;
      CSR_TDATA2:       csr_rdata_o = tselect_q ? '0 : mcontrol_tdata2_q;
      default:          csr_rdata_o = '0;
      endcase
    end

    unique case (csr_op_i)
      CSR_OP_WRITE: csr_wvalue = csr_wdata_i;
      CSR_OP_SET:   csr_wvalue = csr_rdata_o | csr_wdata_i;
      CSR_OP_CLEAR: csr_wvalue = csr_rdata_o & ~csr_wdata_i;
      default:      csr_wvalue = csr_rdata_o;
    endcase
  end

  // ---------------------------------------------------------------------------
  // Debug abstract CSR access
  // ---------------------------------------------------------------------------
  always_comb begin
    debug_csr_error_o = 1'b0;
    unique case (debug_csr_addr_i)
      CSR_DCSR:      debug_csr_rdata_o = dcsr_value;
      CSR_DPC:       debug_csr_rdata_o = dpc_q;
      CSR_DSCRATCH0: debug_csr_rdata_o = dscratch0_q;
      CSR_DSCRATCH1: debug_csr_rdata_o = dscratch1_q;
      CSR_TSELECT:   debug_csr_rdata_o = xlen_t'(tselect_q);
      CSR_TDATA1:    debug_csr_rdata_o = tselect_q ? icount_q : mcontrol_q;
      CSR_TDATA2:    debug_csr_rdata_o = tselect_q ? '0 : mcontrol_tdata2_q;
      default: begin
        debug_csr_rdata_o = '0;
        debug_csr_error_o = debug_csr_req_i;
      end
    endcase
  end

  // ---------------------------------------------------------------------------
  // Sequential CSR state
  // Priority: Debug entry, Debug abstract write, trap entry, MRET, SRET,
  // then an architecturally legal instruction CSR access.
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mstatus_q      <= '0;
      fflags_q       <= 5'h00;
      frm_q          <= 3'b000;
      privilege_mode_q <= PRIV_M;
      mie_q          <= '0;
      mip_sw_q       <= '0;
      sip_sw_q       <= '0;
      medeleg_q      <= '0;
      mideleg_q      <= '0;
      mtvec_q        <= RESET_VECTOR_ADDR_P;
      stvec_q        <= '0;
      scounteren_q   <= '0;
      mscratch_q     <= '0;
      mepc_q         <= '0;
      mcause_q       <= '0;
      mtval_q        <= '0;
      sscratch_q     <= '0;
      sepc_q         <= '0;
      scause_q       <= '0;
      stval_q        <= '0;
      satp_q         <= '0;
      mcountinhibit_q <= '0;
      mcounteren_q    <= '0;
      mcycle_q       <= '0;
      minstret_q     <= '0;
      mhpmcounter3_q <= '0;
      mhpmcounter4_q <= '0;
      mhpmcounter5_q <= '0;
      mhpmcounter6_q <= '0;
      mhpmevent3_q    <= HPM_EVENT_IFETCH_WAIT_CYCLES;
      mhpmevent4_q    <= HPM_EVENT_DATA_WAIT_CYCLES;
      mhpmevent5_q    <= HPM_EVENT_BRANCH_TAKEN;
      mhpmevent6_q    <= HPM_EVENT_INTERRUPT_TAKEN;
      hpm_increment_q <= 4'b0000;
      dcsr_step_q    <= 1'b0;
      dcsr_ebreakm_q <= 1'b0;
      dcsr_cause_q   <= 3'd0;
      dpc_q          <= '0;
      dscratch0_q    <= '0;
      dscratch1_q    <= '0;
      tselect_q      <= 1'b0;
      mcontrol_q     <= xlen_t'(32'h2000_0000);
      mcontrol_tdata2_q <= '0;
      icount_q       <= xlen_t'(32'h3000_0000);
    end else begin
      // Autonomous counter updates precede explicit CSR writes below, so an
      // explicit write to the same counter has architectural priority.
      if (!debug_mode_i && !mcountinhibit_q[0]) begin
        mcycle_q <= mcycle_q + xlen_t'(1);
      end
      if (retire_i && !debug_mode_i && !mcountinhibit_q[2]) begin
        minstret_q <= minstret_q + xlen_t'(1);
      end
      if (trigger_retire_i && !debug_mode_i && (icount_q[13:0] != 14'd0)) begin
        icount_q[13:0] <= icount_q[13:0] - 14'd1;
      end
      if (hpm_increment_q[0] && !hpm_counter_write[0]) begin
        mhpmcounter3_q <= mhpmcounter3_q + xlen_t'(1);
      end
      if (hpm_increment_q[1] && !hpm_counter_write[1]) begin
        mhpmcounter4_q <= mhpmcounter4_q + xlen_t'(1);
      end
      if (hpm_increment_q[2] && !hpm_counter_write[2]) begin
        mhpmcounter5_q <= mhpmcounter5_q + xlen_t'(1);
      end
      if (hpm_increment_q[3] && !hpm_counter_write[3]) begin
        mhpmcounter6_q <= mhpmcounter6_q + xlen_t'(1);
      end
      // A counter write establishes an exact software-visible value and
      // discards both a pending and same-cycle event for that counter.
      hpm_increment_q[0] <= !hpm_counter_write[0] && !debug_mode_i &&
                            hpm_event_active(mhpmevent3_q) && !mcountinhibit_q[3];
      hpm_increment_q[1] <= !hpm_counter_write[1] && !debug_mode_i &&
                            hpm_event_active(mhpmevent4_q) && !mcountinhibit_q[4];
      hpm_increment_q[2] <= !hpm_counter_write[2] && !debug_mode_i &&
                            hpm_event_active(mhpmevent5_q) && !mcountinhibit_q[5];
      hpm_increment_q[3] <= !hpm_counter_write[3] && !debug_mode_i &&
                            hpm_event_active(mhpmevent6_q) && !mcountinhibit_q[6];
      if (fp_commit_i) begin
        fflags_q <= fflags_q | fp_fflags_i;
      end
      if (fp_dirty_i && (mstatus_q[14:13] != 2'b00)) begin
        mstatus_q[14:13] <= 2'b11;
      end

      // State-changing inputs follow the priority documented above.
      if (debug_enter_i) begin
        dpc_q        <= sanitize_mepc(debug_dpc_i);
        dcsr_cause_q <= debug_cause_i;
      end else if (debug_csr_req_i && debug_csr_write_i && !debug_csr_error_o) begin
        unique case (debug_csr_addr_i)
          CSR_DCSR: begin
            dcsr_step_q    <= debug_csr_wdata_i[2];
            dcsr_cause_q   <= debug_csr_wdata_i[8:6];
            dcsr_ebreakm_q <= debug_csr_wdata_i[15];
          end
          CSR_DPC:       dpc_q       <= sanitize_mepc(debug_csr_wdata_i);
          CSR_DSCRATCH0: dscratch0_q <= debug_csr_wdata_i;
          CSR_DSCRATCH1: dscratch1_q <= debug_csr_wdata_i;
          CSR_TSELECT:   tselect_q <= debug_csr_wdata_i[0];
          CSR_TDATA1: begin
            if (tselect_q)
              icount_q <= xlen_t'({4'h3, debug_csr_wdata_i[27:0]});
            else
              mcontrol_q <= xlen_t'({4'h2, debug_csr_wdata_i[27:0]});
          end
          CSR_TDATA2: begin
            if (!tselect_q) mcontrol_tdata2_q <= debug_csr_wdata_i;
          end
          default: begin
          end
        endcase
      end else if (trap_enter_i) begin
        if (trap_delegated_to_s) begin
          sepc_q          <= sanitize_mepc(trap_pc_i);
          scause_q        <= trap_cause_i;
          stval_q         <= trap_value_i;
          mstatus_q[5]    <= mstatus_q[1];
          mstatus_q[1]    <= 1'b0;
          mstatus_q[8]    <= (privilege_mode_q == PRIV_S);
          privilege_mode_q <= PRIV_S;
        end else begin
          mepc_q          <= sanitize_mepc(trap_pc_i);
          mcause_q        <= trap_cause_i;
          mtval_q         <= trap_value_i;
          mstatus_q[7]    <= mstatus_q[3];
          mstatus_q[3]    <= 1'b0;
          mstatus_q[12:11] <= privilege_mode_q;
          privilege_mode_q <= PRIV_M;
        end
      end else if (trap_return_i) begin
        mstatus_q[3]    <= mstatus_q[7];
        mstatus_q[7]    <= 1'b1;
        privilege_mode_q <= (mstatus_q[12:11] == PRIV_M) ? PRIV_M :
                            ((HAS_SMODE && (mstatus_q[12:11] == PRIV_S)) ? PRIV_S : PRIV_U);
        mstatus_q[12:11] <= HAS_UMODE ? PRIV_U : PRIV_M;
        if (mstatus_q[12:11] != PRIV_M) begin
          mstatus_q[17] <= 1'b0;
        end
      end else if (trap_sret_i) begin
        mstatus_q[1]     <= mstatus_q[5];
        mstatus_q[5]     <= 1'b1;
        privilege_mode_q <= (HAS_UMODE && !mstatus_q[8]) ? PRIV_U : PRIV_S;
        mstatus_q[8]     <= 1'b0;
        mstatus_q[17]    <= 1'b0;
      end else if (csr_access_i && !csr_illegal_access_o) begin
        unique case (csr_addr_i)
          CSR_FFLAGS:      fflags_q <= csr_wvalue[4:0];
          CSR_FRM:         frm_q <= csr_wvalue[2:0];
          CSR_FCSR: begin
            fflags_q <= csr_wvalue[4:0];
            frm_q    <= csr_wvalue[7:5];
          end
          CSR_SSTATUS:      mstatus_q <= write_sstatus(mstatus_q, csr_wvalue);
          CSR_SIE:          mie_q <= (mie_q & ~mideleg_q) |
                                      (sanitize_mie(csr_wvalue) & mideleg_q);
          CSR_STVEC:        stvec_q <= sanitize_mtvec(csr_wvalue);
          CSR_SCOUNTEREN:   scounteren_q <= csr_wvalue & xlen_t'(MCOUNTEREN_WRITABLE_MASK);
          CSR_SSCRATCH:     sscratch_q <= csr_wvalue;
          CSR_SEPC:         sepc_q <= sanitize_mepc(csr_wvalue);
          CSR_SCAUSE:       scause_q <= csr_wvalue;
          CSR_STVAL:        stval_q <= csr_wvalue;
          CSR_SIP:          sip_sw_q <= sanitize_sip(csr_wvalue & mideleg_q);
          CSR_SATP:         satp_q <= sanitize_satp(satp_q, csr_wvalue);
          CSR_MSTATUS:      mstatus_q      <= sanitize_mstatus(csr_wvalue);
          CSR_MIE:          mie_q          <= sanitize_mie(csr_wvalue);
          CSR_MTVEC:        mtvec_q        <= sanitize_mtvec(csr_wvalue);
          CSR_MSCRATCH:     mscratch_q     <= csr_wvalue;
          CSR_MEPC:         mepc_q         <= sanitize_mepc(csr_wvalue);
          CSR_MCAUSE:       mcause_q       <= csr_wvalue;
          CSR_MTVAL:        mtval_q        <= csr_wvalue;
          CSR_MIP:          mip_sw_q       <= sanitize_mip(csr_wvalue);
          CSR_MEDELEG:      medeleg_q      <= sanitize_medeleg(csr_wvalue);
          CSR_MIDELEG:      mideleg_q      <= sanitize_mideleg(csr_wvalue);
          CSR_MCOUNTINHIBIT: mcountinhibit_q <= csr_wvalue & xlen_t'(32'h0000_007d);
          CSR_MCOUNTEREN:    mcounteren_q <= HAS_MCOUNTEREN ?
                                               (csr_wvalue & xlen_t'(MCOUNTEREN_WRITABLE_MASK)) :
                                               '0;
          CSR_MCYCLE:        mcycle_q <= csr_wvalue;
          CSR_MINSTRET:      minstret_q <= csr_wvalue;
          CSR_MHPMCOUNTER3:  mhpmcounter3_q <= csr_wvalue;
          CSR_MHPMCOUNTER4:  mhpmcounter4_q <= csr_wvalue;
          CSR_MHPMCOUNTER5:  mhpmcounter5_q <= csr_wvalue;
          CSR_MHPMCOUNTER6:  mhpmcounter6_q <= csr_wvalue;
          CSR_MHPMEVENT3:    mhpmevent3_q <= sanitize_hpm_event(csr_wvalue);
          CSR_MHPMEVENT4:    mhpmevent4_q <= sanitize_hpm_event(csr_wvalue);
          CSR_MHPMEVENT5:    mhpmevent5_q <= sanitize_hpm_event(csr_wvalue);
          CSR_MHPMEVENT6:    mhpmevent6_q <= sanitize_hpm_event(csr_wvalue);
          CSR_DCSR: begin
            dcsr_step_q    <= csr_wvalue[2];
            dcsr_cause_q   <= csr_wvalue[8:6];
            dcsr_ebreakm_q <= csr_wvalue[15];
          end
          CSR_DPC:       dpc_q       <= sanitize_mepc(csr_wvalue);
          CSR_DSCRATCH0: dscratch0_q <= csr_wvalue;
          CSR_DSCRATCH1: dscratch1_q <= csr_wvalue;
          CSR_TSELECT:   tselect_q <= csr_wvalue[0];
          CSR_TDATA1: begin
            if (tselect_q)
              icount_q <= xlen_t'({4'h3, csr_wvalue[27:0]});
            else
              mcontrol_q <= xlen_t'({4'h2, csr_wvalue[27:0]});
          end
          CSR_TDATA2: begin
            if (!tselect_q) mcontrol_tdata2_q <= csr_wvalue;
          end
          default: begin
          end
        endcase
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Architectural state exports
  // ---------------------------------------------------------------------------
  assign mtvec_o          = mtvec_q;
  assign mepc_o           = mepc_q;
  assign stvec_o          = stvec_q;
  assign sepc_o           = sepc_q;
  assign medeleg_o        = medeleg_q;
  assign dpc_o            = dpc_q;
  assign dcsr_step_o      = dcsr_step_q;
  assign dcsr_ebreakm_o   = dcsr_ebreakm_q;
  assign dcsr_cause_o     = dcsr_cause_q;
  assign trigger_mcontrol_o = mcontrol_q;
  assign trigger_tdata2_o  = mcontrol_tdata2_q;
  assign trigger_icount_o  = icount_q;
  assign privilege_mode_o  = privilege_mode_q;
  assign mstatus_tsr_o     = mstatus_q[22];
  assign mstatus_tw_o      = mstatus_q[21];
  assign mstatus_mprv_o    = HAS_MPRV && mstatus_q[17];
  assign mstatus_mpp_o     = privilege_mode_e'(mstatus_q[12:11]);
  assign mstatus_tvm_o     = mstatus_q[20];
  assign mstatus_sum_o     = mstatus_q[18];
  assign mstatus_mxr_o     = mstatus_q[19];
  assign satp_o            = satp_q;
  assign frm_o             = frm_q;
  assign fs_off_o          = (mstatus_q[14:13] == 2'b00);

endmodule
