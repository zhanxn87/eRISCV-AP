// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

import riscv_pkg::*;

module zicbom_metadata_tb;
  localparam xlen_t TARGET_ADDR = 64'h0000_0000_0000_1000;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic fetch_enable = 1'b0;
  int unsigned cbo_count;
  cbo_op_e cbo_seen_op [0:2];
  xlen_t cbo_seen_addr [0:2];

  riscv_wrapper dut (
    .clk(clk),
    .rst_n(rst_n),
    .fetch_enable_i(fetch_enable),
    .boot_addr_i(xlen_t'(RESET_VECTOR_ADDR)),
    .debug_halt_req_i(1'b0),
    .debug_resume_req_i(1'b0),
    .debug_halted_o(),
    .debug_running_o(),
    .debug_pc_o(),
    .debug_cause_o(),
    .sfence_vma_o(),
    .sfence_vma_vaddr_o(),
    .sfence_vma_asid_o(),
    .irq_i('0)
  );

  always #5 clk = ~clk;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cbo_count <= 0;
    end else if (dut.data_cbo_req && dut.data_cbo_ready) begin
      if (cbo_count >= 3)
        $fatal(1, "unexpected extra Zicbom request");
      cbo_seen_op[cbo_count] <= dut.data_cbo_op;
      cbo_seen_addr[cbo_count] <= dut.data_cbo_addr;
      cbo_count <= cbo_count + 1;
    end
  end

  task automatic check(input logic condition, input string message);
    if (!condition)
      $fatal(1, "ZICBOM_METADATA_TB: %s", message);
  endtask

  initial begin
    // Prepare a dirty 0x1000 line in M-mode, enter S-mode at 0xb0, then
    // clean, flush, and invalidate it. The final S-mode reload sees 0x66.
    dut.instr_mem_i.sram_i.mem[16'h20] = 32'h0000_10b7; // lui x1, 1
    dut.instr_mem_i.sram_i.mem[16'h21] = 32'h0550_0113; // addi x2, x0, 0x55
    dut.instr_mem_i.sram_i.mem[16'h22] = 32'h0020_b023; // sd x2, 0(x1)
    dut.instr_mem_i.sram_i.mem[16'h23] = 32'h0000_12b7; // lui x5, 1
    dut.instr_mem_i.sram_i.mem[16'h24] = 32'h0012_d293; // srli x5, x5, 1
    dut.instr_mem_i.sram_i.mem[16'h25] = 32'h3002_9073; // csrw mstatus, x5 (MPP=S)
    dut.instr_mem_i.sram_i.mem[16'h26] = 32'h0b00_0313; // addi x6, x0, 0xb0
    dut.instr_mem_i.sram_i.mem[16'h27] = 32'h3413_1073; // csrw mepc, x6
    dut.instr_mem_i.sram_i.mem[16'h28] = 32'h3020_0073; // mret
    dut.instr_mem_i.sram_i.mem[16'h29] = 32'h0000_0013; // nop
    dut.instr_mem_i.sram_i.mem[16'h2a] = 32'h0000_0013; // nop
    dut.instr_mem_i.sram_i.mem[16'h2b] = 32'h0000_0013; // nop
    dut.instr_mem_i.sram_i.mem[16'h2c] = 32'h0010_a00f; // cbo.clean (x1)
    dut.instr_mem_i.sram_i.mem[16'h2d] = 32'h0660_0113; // addi x2, x0, 0x66
    dut.instr_mem_i.sram_i.mem[16'h2e] = 32'h0020_b023; // sd x2, 0(x1)
    dut.instr_mem_i.sram_i.mem[16'h2f] = 32'h0020_a00f; // cbo.flush (x1)
    dut.instr_mem_i.sram_i.mem[16'h30] = 32'h0000_b183; // ld x3, 0(x1)
    dut.instr_mem_i.sram_i.mem[16'h31] = 32'h0770_0113; // addi x2, x0, 0x77
    dut.instr_mem_i.sram_i.mem[16'h32] = 32'h0020_b023; // sd x2, 0(x1)
    dut.instr_mem_i.sram_i.mem[16'h33] = 32'h0000_a00f; // cbo.inval (x1)
    dut.instr_mem_i.sram_i.mem[16'h34] = 32'h0000_b203; // ld x4, 0(x1)
    dut.instr_mem_i.sram_i.mem[16'h35] = 32'h0000_006f; // jal x0, 0

    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    fetch_enable = 1'b1;

    repeat (400) begin
      @(posedge clk);
      #1;
      if ((cbo_count == 3) &&
          (dut.riscv_core_i.id_stage_i.regfile_i.regs_q[4] == 64'h66)) begin
        check(dut.riscv_core_i.ex_stage_i.privilege_mode == PRIV_S,
              "CBO program did not remain in S-mode");
        check(cbo_seen_op[0] == CBO_CLEAN, "first operation was not CBO.CLEAN");
        check(cbo_seen_op[1] == CBO_FLUSH, "second operation was not CBO.FLUSH");
        check(cbo_seen_op[2] == CBO_INVAL, "third operation was not CBO.INVAL");
        check(cbo_seen_addr[0] == TARGET_ADDR && cbo_seen_addr[1] == TARGET_ADDR &&
              cbo_seen_addr[2] == TARGET_ADDR, "CBO effective address mismatch");
        check(dut.cache_backing_mem_i.mem[TARGET_ADDR >> 6][63:0] == 64'h66,
              "clean/flush writeback or invalidate discard behavior is wrong");
        $display("ZICBOM_METADATA_TB PASS: S-mode decode, CBO pipeline, and D-Cache semantics");
        $finish;
      end
    end
    $fatal(1, "timeout waiting for Zicbom program completion count=%0d x4=%h",
           cbo_count, dut.riscv_core_i.id_stage_i.regfile_i.regs_q[4]);
  end
endmodule
