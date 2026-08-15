// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

import riscv_pkg::*;

module sfence_vma_metadata_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic fetch_enable = 1'b0;
  logic sfence_vma;
  xlen_t sfence_vma_vaddr;
  logic [15:0] sfence_vma_asid;
  logic sfence_seen;

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
    .sfence_vma_o(sfence_vma),
    .sfence_vma_vaddr_o(sfence_vma_vaddr),
    .sfence_vma_asid_o(sfence_vma_asid),
    .irq_i('0)
  );

  always #5 clk = ~clk;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sfence_seen <= 1'b0;
    end else if (sfence_vma) begin
      if (sfence_vma_vaddr != 64'h0000_0000_4000_0000)
        $fatal(1, "SFENCE.VMA VA selector mismatch: %h", sfence_vma_vaddr);
      if (sfence_vma_asid != 16'h0123)
        $fatal(1, "SFENCE.VMA ASID selector mismatch: %h", sfence_vma_asid);
      sfence_seen <= 1'b1;
    end
  end

  initial begin
    // lui x5,0x40000; addi x6,x0,0x123; sfence.vma x5,x6; loop.
    dut.instr_mem_i.sram_i.mem[16'h20] = 32'h4000_02b7;
    dut.instr_mem_i.sram_i.mem[16'h21] = 32'h1230_0313;
    dut.instr_mem_i.sram_i.mem[16'h22] = 32'h1262_8073;
    dut.instr_mem_i.sram_i.mem[16'h23] = 32'h0000_006f;

    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    fetch_enable = 1'b1;
    repeat (100) begin
      @(posedge clk);
      if (sfence_seen) begin
        $display("SFENCE_VMA_METADATA_TB PASS: retired VA/ASID selectors");
        $finish;
      end
    end
    $fatal(1, "timeout waiting for SFENCE.VMA retirement");
  end
endmodule
