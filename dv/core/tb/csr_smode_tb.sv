// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

import riscv_pkg::*;

module csr_smode_tb;
  logic clk;
  logic rst_n;
  logic csr_access;
  logic [1:0] csr_op;
  logic [11:0] csr_addr;
  logic csr_write_intent;
  xlen_t csr_wdata;
  xlen_t csr_rdata;
  logic csr_illegal_access;
  logic trap_enter;
  xlen_t trap_pc;
  xlen_t trap_cause;
  xlen_t trap_value;
  logic trap_return;
  logic trap_sret;
  logic debug_enter;
  xlen_t debug_dpc;
  logic [2:0] debug_cause;
  logic debug_mode;
  logic retire;
  logic [1:0] instret_pending;
  logic [31:0] irq;
  logic [63:0] mtime;
  logic [HPM_EVENT_COUNT-1:0] hpm_event;
  logic fp_commit;
  logic fp_dirty;
  logic [4:0] fp_fflags;
  logic [2:0] frm;
  logic fs_off;
  logic debug_csr_req;
  logic debug_csr_write;
  logic [11:0] debug_csr_addr;
  xlen_t debug_csr_wdata;
  xlen_t debug_csr_rdata;
  logic debug_csr_error;
  logic trigger_retire;
  xlen_t trigger_mcontrol;
  xlen_t trigger_tdata2;
  xlen_t trigger_icount;
  xlen_t mtvec;
  xlen_t mepc;
  xlen_t stvec;
  xlen_t sepc;
  xlen_t medeleg;
  xlen_t dpc;
  logic dcsr_step;
  logic dcsr_ebreakm;
  logic [2:0] dcsr_cause;
  logic interrupt_ready;
  logic interrupt_to_s;
  xlen_t interrupt_cause;
  privilege_mode_e privilege_mode;
  logic mstatus_tsr;
  logic mstatus_tw;
  logic mstatus_mprv;
  privilege_mode_e mstatus_mpp;
  logic mstatus_tvm;
  logic mstatus_sum;
  logic mstatus_mxr;
  xlen_t satp;

  csr_file dut (
    .clk,
    .rst_n,
    .csr_access_i(csr_access),
    .csr_op_i(csr_op),
    .csr_addr_i(csr_addr),
    .csr_write_intent_i(csr_write_intent),
    .csr_wdata_i(csr_wdata),
    .csr_rdata_o(csr_rdata),
    .csr_illegal_access_o(csr_illegal_access),
    .trap_enter_i(trap_enter),
    .trap_pc_i(trap_pc),
    .trap_cause_i(trap_cause),
    .trap_value_i(trap_value),
    .trap_return_i(trap_return),
    .trap_sret_i(trap_sret),
    .debug_enter_i(debug_enter),
    .debug_dpc_i(debug_dpc),
    .debug_cause_i(debug_cause),
    .debug_mode_i(debug_mode),
    .retire_i(retire),
    .instret_pending_i(instret_pending),
    .irq_i(irq),
    .mtime_i(mtime),
    .hpm_event_i(hpm_event),
    .fp_commit_i(fp_commit),
    .fp_dirty_i(fp_dirty),
    .fp_fflags_i(fp_fflags),
    .frm_o(frm),
    .fs_off_o(fs_off),
    .debug_csr_req_i(debug_csr_req),
    .debug_csr_write_i(debug_csr_write),
    .debug_csr_addr_i(debug_csr_addr),
    .debug_csr_wdata_i(debug_csr_wdata),
    .debug_csr_rdata_o(debug_csr_rdata),
    .debug_csr_error_o(debug_csr_error),
    .trigger_retire_i(trigger_retire),
    .trigger_mcontrol_o(trigger_mcontrol),
    .trigger_tdata2_o(trigger_tdata2),
    .trigger_icount_o(trigger_icount),
    .mtvec_o(mtvec),
    .mepc_o(mepc),
    .stvec_o(stvec),
    .sepc_o(sepc),
    .medeleg_o(medeleg),
    .dpc_o(dpc),
    .dcsr_step_o(dcsr_step),
    .dcsr_ebreakm_o(dcsr_ebreakm),
    .dcsr_cause_o(dcsr_cause),
    .interrupt_ready_o(interrupt_ready),
    .interrupt_to_s_o(interrupt_to_s),
    .interrupt_cause_o(interrupt_cause),
    .privilege_mode_o(privilege_mode),
    .mstatus_tsr_o(mstatus_tsr),
    .mstatus_tw_o(mstatus_tw),
    .mstatus_mprv_o(mstatus_mprv),
    .mstatus_mpp_o(mstatus_mpp),
    .mstatus_tvm_o(mstatus_tvm),
    .mstatus_sum_o(mstatus_sum),
    .mstatus_mxr_o(mstatus_mxr),
    .satp_o(satp)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task automatic check(input logic condition, input string message);
    if (!condition)
      $fatal(1, "CSR_SMODE_TB: %s", message);
  endtask

  task automatic write_csr(input logic [11:0] addr, input xlen_t value);
    begin
      csr_access = 1'b1;
      csr_op = CSR_OP_WRITE;
      csr_addr = addr;
      csr_write_intent = 1'b1;
      csr_wdata = value;
      @(posedge clk);
      #1;
      check(!csr_illegal_access, $sformatf("CSR %03h unexpectedly illegal", addr));
      csr_access = 1'b0;
      csr_op = CSR_OP_NONE;
      csr_addr = '0;
      csr_write_intent = 1'b0;
      csr_wdata = '0;
    end
  endtask

  task automatic read_csr(input logic [11:0] addr, input xlen_t expected);
    begin
      csr_access = 1'b1;
      csr_op = CSR_OP_NONE;
      csr_addr = addr;
      csr_write_intent = 1'b0;
      #1;
      check(!csr_illegal_access, $sformatf("CSR %03h unexpectedly illegal", addr));
      check(csr_rdata == expected,
            $sformatf("CSR %03h expected %016h got %016h", addr, expected, csr_rdata));
      csr_access = 1'b0;
      csr_addr = '0;
    end
  endtask

  initial begin
    rst_n = 1'b0;
    csr_access = 1'b0;
    csr_op = CSR_OP_NONE;
    csr_addr = '0;
    csr_write_intent = 1'b0;
    csr_wdata = '0;
    trap_enter = 1'b0;
    trap_pc = '0;
    trap_cause = '0;
    trap_value = '0;
    trap_return = 1'b0;
    trap_sret = 1'b0;
    debug_enter = 1'b0;
    debug_dpc = '0;
    debug_cause = '0;
    debug_mode = 1'b0;
    retire = 1'b0;
    instret_pending = '0;
    irq = '0;
    mtime = '0;
    hpm_event = '0;
    fp_commit = 1'b0;
    fp_dirty = 1'b0;
    fp_fflags = '0;
    debug_csr_req = 1'b0;
    debug_csr_write = 1'b0;
    debug_csr_addr = '0;
    debug_csr_wdata = '0;
    trigger_retire = 1'b0;

    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    #1;

    write_csr(CSR_STVEC, 64'h100);
    write_csr(CSR_SATP, 64'h8123_0000_0000_0042);
    read_csr(CSR_SATP, 64'h8123_0000_0000_0042);
    // Unsupported MODE writes must leave SATP unchanged.
    write_csr(CSR_SATP, 64'h9123_0000_0000_0077);
    read_csr(CSR_SATP, 64'h8123_0000_0000_0042);
    write_csr(CSR_MIDELEG, 64'h200);
    write_csr(CSR_MIE, 64'h200);
    check(stvec == 64'h100, "STVEC write did not commit");

    trap_return = 1'b1;
    @(posedge clk);
    #1;
    trap_return = 1'b0;
    check(privilege_mode == PRIV_U, "MRET did not enter U mode");

    irq[11] = 1'b1;
    #1;
    check(interrupt_ready, "delegated external interrupt was not accepted");
    check(interrupt_to_s, "delegated external interrupt did not target S mode");
    check(interrupt_cause == ((xlen_t'(1) << (CORE_XLEN - 1)) | xlen_t'(9)),
          "delegated external interrupt cause is not SEIP");

    trap_enter = 1'b1;
    trap_pc = 64'h80;
    trap_cause = interrupt_cause;
    trap_value = '0;
    @(posedge clk);
    #1;
    trap_enter = 1'b0;
    irq[11] = 1'b0;
    check(privilege_mode == PRIV_S, "delegated interrupt did not enter S mode");
    check(sepc == 64'h80, "delegated interrupt did not save SEPC");
    read_csr(CSR_SCAUSE, (xlen_t'(1) << (CORE_XLEN - 1)) | xlen_t'(9));

    write_csr(CSR_SSCRATCH, 64'h55aa);
    read_csr(CSR_SSCRATCH, 64'h55aa);
    write_csr(CSR_SATP, 64'h8000_0000_0000_0042);
    read_csr(CSR_SATP, 64'h8000_0000_0000_0042);

    // Return to M, set TVM with MPP=S, then verify S-mode SATP access traps.
    trap_enter = 1'b1;
    trap_pc = 64'h90;
    trap_cause = 64'd11;
    @(posedge clk);
    #1 trap_enter = 1'b0;
    check(privilege_mode == PRIV_M, "machine trap did not enter M mode");
    write_csr(CSR_MSTATUS, (xlen_t'(PRIV_S) << 11) | (xlen_t'(1) << 20));
    trap_return = 1'b1;
    @(posedge clk);
    #1 trap_return = 1'b0;
    check(privilege_mode == PRIV_S && mstatus_tvm, "MRET did not restore S with TVM");
    csr_access = 1'b1;
    csr_addr = CSR_SATP;
    #1 check(csr_illegal_access, "S-mode SATP access ignored mstatus.TVM");
    csr_access = 1'b0;
    csr_addr = '0;

    trap_sret = 1'b1;
    @(posedge clk);
    #1;
    trap_sret = 1'b0;
    check(privilege_mode == PRIV_U, "SRET did not restore U mode");

    $display("CSR_SMODE_TB PASS: delegated SEIP, S CSR access, and SRET");
    $finish;
  end
endmodule
