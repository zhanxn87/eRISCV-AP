// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

import riscv_pkg::*;

// Phase 12 top-level testbench.
// Plusargs select the testcase image, oracle style, optional wave dump, and
// debug/interrupt stimulus points for one self-contained simulation run.
module riscv_tb #(
  parameter int IMEM_READ_LATENCY = 1,
  parameter int DMEM_READ_LATENCY = 1,
  parameter int IMEM_WORD_ADDR_WIDTH = 17,
  parameter int DMEM_WORD_ADDR_WIDTH = 17
);

  localparam CLK_PERIOD = 10;
  localparam int INSTR_MEM_DEPTH = 1 << IMEM_WORD_ADDR_WIDTH;
  localparam int DATA_MEM_DEPTH = 1 << DMEM_WORD_ADDR_WIDTH;
  localparam logic [31:0] INSTR_NOP = 32'h0000_0013;
  localparam string TB_PHASE_NAME = "ERISCV_M2";

  logic clk;
  logic rst_n;
  logic fetch_enable_i;
  logic [31:0] irq_i;
  xlen_t       boot_addr;
  string tc_name;
  string instr_mem_file;
  string oracle_mode;
  string expected_regs_file;
  string reference_output_file;
  string data_mem_file;
  string fence_check_file;
  string dump_file;
  int unsigned max_cycles;
  int unsigned sig_base;
  int unsigned tohost_addr;
  xlen_t       tohost_pass_value;
  xlen_t       tohost_fail_value;
  xlen_t       act_tohost_value;
  xlen_t       act_tohost_char_value;
  xlen_t       boot_addr_arg;
  int unsigned irq_start_cycle;
  int unsigned irq_duration;
  int irq_on_muldiv_busy;
  int debug_halt_cycle;
  int debug_resume_cycle;
  int expected_debug_cause;
  int reset_on_muldiv_busy;
  int completion_reg;
  xlen_t       completion_value;
  paddr_t      fence_check_addr;
  xlen_t       fence_check_value;
  int unsigned run_cycle;
  bit has_expected_regs;
  bit has_reference_output;
  bit has_act_oracle;
  bit has_data_mem_file;
  bit has_fence_check;
  bit has_completion;
  bit completion_seen;
  bit fence_check_seen;
  xlen_t fence_check_actual;
  int fence_check_handle;
  int fence_check_status;
  bit saw_debug_halted;
  bit debug_resume_armed;
  bit debug_resume_sent;
  bit reset_injected;
  bit irq_muldiv_injected;
  bit irq_muldiv_active;
  int unsigned irq_muldiv_tail_cycles;
  logic debug_halt_req;
  logic debug_resume_req;
  logic debug_halted;
  logic debug_running;
  xlen_t       debug_pc;
  logic [2:0] debug_cause;

  initial clk = 1'b0;
  always #(CLK_PERIOD / 2) clk = ~clk;

  // Optional waveform dumping is controlled entirely by plusargs so the same
  // compiled testbench works for fast regression and interactive debug.
  initial begin
    if ($test$plusargs("dump_wave")) begin
      if (!$value$plusargs("dump_file=%s", dump_file)) begin
        dump_file = "waves/riscv_tb.fst";
      end
      $dumpfile(dump_file);
      $dumpvars(0, riscv_tb);
      $display("TB WAVE: dumping waveform to %s", dump_file);
    end
  end

  riscv_wrapper #(
    .IMEM_READ_LATENCY(IMEM_READ_LATENCY),
    .DMEM_READ_LATENCY(DMEM_READ_LATENCY),
    .IMEM_WORD_ADDR_WIDTH(IMEM_WORD_ADDR_WIDTH),
    .DMEM_WORD_ADDR_WIDTH(DMEM_WORD_ADDR_WIDTH)
  ) dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .fetch_enable_i (fetch_enable_i),
    .boot_addr_i    (boot_addr),
    .debug_halt_req_i(debug_halt_req),
    .debug_resume_req_i(debug_resume_req),
    .debug_halted_o (debug_halted),
    .debug_running_o(debug_running),
    .debug_pc_o     (debug_pc),
    .debug_cause_o  (debug_cause),
    .sfence_vma_o(),
    .sfence_vma_vaddr_o(),
    .sfence_vma_asid_o(),
    .irq_i          (irq_i)
  );

  `include "tb_common.svh"

  always @(posedge clk) begin
    if (rst_n && dut.imem_rvalid) begin
      check(!$isunknown(dut.imem_rdata), "instruction memory returned unknown data");
    end
    if (rst_n && fetch_enable_i && has_fence_check &&
        dut.cache_flush_done && !fence_check_seen) begin
      fence_check_actual = dut.cache_backing_mem_i.mem[
          fence_check_addr[DMEM_WORD_ADDR_WIDTH+2:6]][fence_check_addr[5:3] * 64 +: 64];
      check(fence_check_actual === fence_check_value,
            $sformatf("FENCE writeback at %012h expected %016h, got %016h",
                      fence_check_addr, fence_check_value, fence_check_actual));
      $display("TB FENCE: backing[%012h]=%016h PASS",
               fence_check_addr, fence_check_actual);
      fence_check_seen = 1'b1;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      run_cycle <= 0;
      irq_i <= 32'h0000_0000;
    end else if (fetch_enable_i) begin
      if ((irq_on_muldiv_busy != 0) && !irq_muldiv_injected &&
          dut.riscv_core_i.ex_stage_i.muldiv_busy) begin
        irq_i <= 32'h0000_0800;
        irq_muldiv_injected <= 1'b1;
        irq_muldiv_active <= 1'b1;
        // irq_i is registered in this TB, so retain it beyond busy deassertion
        // and through an instruction-boundary sampling opportunity.
        irq_muldiv_tail_cycles <= 4;
        $display("TB IRQ: asserting external IRQ while muldiv_busy is asserted");
      end else if (irq_muldiv_active) begin
        // A multi-cycle M/D instruction blocks trap acceptance until its
        // completion boundary. Hold the level request for four following
        // non-busy cycles; the testcase handler masks MEIE, so this cannot
        // create a second interrupt after MRET.
        irq_i <= 32'h0000_0800;
        if (!dut.riscv_core_i.ex_stage_i.muldiv_busy) begin
          if (irq_muldiv_tail_cycles == 0)
            irq_muldiv_active <= 1'b0;
          else
            irq_muldiv_tail_cycles <= irq_muldiv_tail_cycles - 1'b1;
        end
      end else if ((irq_duration != 0) &&
          (run_cycle >= irq_start_cycle) &&
          (run_cycle < (irq_start_cycle + irq_duration))) begin
        irq_i <= 32'h0000_0800;
      end else begin
        irq_i <= 32'h0000_0000;
      end
      run_cycle <= run_cycle + 1;
    end else begin
      irq_i <= 32'h0000_0000;
    end
  end

  // One-shot reset injection for true mid-operation M/D reset coverage.
  // The trigger observes muldiv_wait rather than an estimated instruction
  // cycle. reset_injected survives the DUT reset to prevent re-triggering.
  always @(negedge clk) begin
    if (rst_n && fetch_enable_i && (reset_on_muldiv_busy != 0) &&
        !reset_injected && dut.riscv_core_i.muldiv_wait) begin
      $display("TB RESET: injecting reset while muldiv_wait is asserted");
      rst_n <= 1'b0;
      reset_injected <= 1'b1;
    end else if (!rst_n && reset_injected) begin
      rst_n <= 1'b1;
    end
  end

  always @(negedge clk or negedge rst_n) begin
    if (!rst_n) begin
      debug_halt_req <= 1'b0;
      debug_resume_req <= 1'b0;
      saw_debug_halted <= 1'b0;
      debug_resume_armed <= 1'b0;
      debug_resume_sent <= 1'b0;
    end else if (fetch_enable_i) begin
      debug_halt_req <= (debug_halt_cycle >= 0) && (run_cycle == debug_halt_cycle);
      if ((debug_resume_cycle >= 0) && (run_cycle >= debug_resume_cycle)) begin
        debug_resume_armed <= 1'b1;
      end
      debug_resume_req <= debug_resume_armed && debug_halted && !debug_resume_sent;
      if (debug_halted) begin
        saw_debug_halted <= 1'b1;
      end
      if (debug_resume_armed && debug_halted && !debug_resume_sent) begin
        debug_resume_sent <= 1'b1;
      end
    end else begin
      debug_halt_req <= 1'b0;
      debug_resume_req <= 1'b0;
    end
  end

  always @(posedge clk) begin
    if (rst_n && fetch_enable_i) begin
      #1;
      if (debug_halted) begin
        saw_debug_halted = 1'b1;
      end
      if (has_act_oracle && dut.riscv_core_i.data_req_o && dut.riscv_core_i.data_we_o) begin
        if (dut.riscv_core_i.data_addr_o == (paddr_t'(tohost_addr) << 3)) begin
          act_tohost_char_value <= dut.riscv_core_i.data_wdata_o;
        end else if ((dut.riscv_core_i.data_addr_o == ((paddr_t'(tohost_addr) + paddr_t'(1)) << 3)) &&
                     ((dut.riscv_core_i.data_wdata_o == xlen_t'(32'h1010_0000)) ||
                      (dut.riscv_core_i.data_wdata_o == xlen_t'(32'h0101_0000)))) begin
          $display("TB ACT IO: char=0x%02h (%c)", act_tohost_char_value[7:0], act_tohost_char_value[7:0]);
        end
        if ((dut.riscv_core_i.data_addr_o >= paddr_t'(32'h0004_05a0)) &&
            (dut.riscv_core_i.data_addr_o < paddr_t'(32'h0004_07a0))) begin
          $display("TB ACT STORE: cycle=%0d addr=%012h data=%016h be=%0h",
                   run_cycle,
                   dut.riscv_core_i.data_addr_o,
                   dut.riscv_core_i.data_wdata_o,
                   dut.riscv_core_i.data_be_o);
        end
      end
    end
  end

  initial begin
    if (!$value$plusargs("tc=%s", tc_name)) begin
      $fatal(1, "No testcase selected. Pass +tc=<name>.");
    end
    if (!$value$plusargs("instr_mem_file=%s", instr_mem_file)) begin
      $fatal(1, "No instruction-memory file selected.");
    end
    if (!$value$plusargs("oracle_mode=%s", oracle_mode)) begin
      oracle_mode = "";
    end
    has_expected_regs = $value$plusargs("expected_regs_file=%s", expected_regs_file);
    has_reference_output = $value$plusargs("reference_output_file=%s", reference_output_file);
    has_data_mem_file = $value$plusargs("data_mem_file=%s", data_mem_file);
    has_fence_check = $value$plusargs("fence_check_file=%s", fence_check_file);
    fence_check_seen = 1'b0;
    if (has_fence_check) begin
      fence_check_handle = $fopen(fence_check_file, "r");
      if (fence_check_handle == 0) begin
        $fatal(1, "Unable to open FENCE check file: %s", fence_check_file);
      end
      fence_check_status = $fscanf(fence_check_handle, "%h %h\n",
                                   fence_check_addr, fence_check_value);
      $fclose(fence_check_handle);
      if (fence_check_status != 2) begin
        $fatal(1, "Malformed FENCE check file: %s", fence_check_file);
      end
    end
    has_completion = $value$plusargs("completion_reg=%d", completion_reg);
    if (has_completion && !$value$plusargs("completion_value=%h", completion_value)) begin
      $fatal(1, "completion_reg requires completion_value.");
    end
    if (has_completion && (completion_reg < 0 || completion_reg >= 32)) begin
      $fatal(1, "completion_reg is out of range: %0d", completion_reg);
    end
    if (!$value$plusargs("max_cycles=%d", max_cycles)) begin
      max_cycles = 80;
    end
    if (!$value$plusargs("sig_base=%h", sig_base)) begin
      sig_base = 'h80;
    end
    if (!$value$plusargs("tohost_addr=%h", tohost_addr)) begin
      tohost_addr = 'h0;
    end
    if (!$value$plusargs("tohost_pass_value=%h", tohost_pass_value)) begin
      tohost_pass_value = xlen_t'(32'h0000_0001);
    end
    if (!$value$plusargs("tohost_fail_value=%h", tohost_fail_value)) begin
      tohost_fail_value = xlen_t'(32'h0000_0003);
    end
    if (!$value$plusargs("boot_addr=%h", boot_addr_arg)) begin
      boot_addr_arg = 'h0;
    end
    if (!$value$plusargs("irq_start_cycle=%d", irq_start_cycle)) begin
      irq_start_cycle = 0;
    end
    if (!$value$plusargs("irq_duration=%d", irq_duration)) begin
      irq_duration = 0;
    end
    if (!$value$plusargs("irq_on_muldiv_busy=%d", irq_on_muldiv_busy)) begin
      irq_on_muldiv_busy = 0;
    end
    if (!$value$plusargs("debug_halt_cycle=%d", debug_halt_cycle)) begin
      debug_halt_cycle = -1;
    end
    if (!$value$plusargs("debug_resume_cycle=%d", debug_resume_cycle)) begin
      debug_resume_cycle = -1;
    end
    if (!$value$plusargs("expected_debug_cause=%d", expected_debug_cause)) begin
      expected_debug_cause = -1;
    end
    if (!$value$plusargs("reset_on_muldiv_busy=%d", reset_on_muldiv_busy)) begin
      reset_on_muldiv_busy = 0;
    end
    has_act_oracle = (oracle_mode == "act");
    if (oracle_mode == "regs") begin
      has_act_oracle = 1'b0;
    end else if (oracle_mode == "signature") begin
      has_act_oracle = 1'b0;
    end else if ((oracle_mode != "") && (oracle_mode != "act")) begin
      $fatal(1, "Unknown oracle mode %s. Use regs, signature, or act.", oracle_mode);
    end
    if (!has_expected_regs && !has_reference_output && !has_act_oracle) begin
      $fatal(1, "No oracle selected. Pass +expected_regs_file=<path>, +reference_output_file=<path>, or +oracle_mode=act.");
    end

    $display("=== eRISCV-M2 testcase: %s ===", tc_name);
    $display("TB loading instruction memory: %s", instr_mem_file);
    if (has_expected_regs) begin
      $display("TB expected-register oracle: %s", expected_regs_file);
    end
    if (has_reference_output) begin
      $display("TB reference-output oracle: %s", reference_output_file);
      $display("TB signature base doubleword index: 0x%0h", sig_base);
      $display("TB tohost doubleword index: 0x%0h", tohost_addr);
    end
    if (has_act_oracle) begin
      $display("TB ACT oracle: tohost doubleword index=0x%0h pass=%016h fail=%016h",
               tohost_addr, tohost_pass_value, tohost_fail_value);
    end
    if (has_completion) begin
      $display("TB completion oracle: x%0d=%016h", completion_reg, completion_value);
    end
    boot_addr = boot_addr_arg;
    $display("TB boot address: 0x%016h", boot_addr);
    $display("TB memory read latency: imem=%0d dmem=%0d",
             IMEM_READ_LATENCY, DMEM_READ_LATENCY);
    if (irq_duration != 0) begin
      $display("TB IRQ: irq_i[11] start_cycle=%0d duration=%0d",
               irq_start_cycle, irq_duration);
    end
    if (debug_halt_cycle >= 0) begin
      $display("TB DEBUG: external halt cycle=%0d resume cycle=%0d",
               debug_halt_cycle, debug_resume_cycle);
    end
    init_instruction_memory(INSTR_NOP);
    init_data_memory('0);
    $readmemh(instr_mem_file, dut.instr_mem_i.sram_i.mem);
    if (has_data_mem_file) begin
      $display("TB loading data memory: %s", data_mem_file);
      $readmemh(data_mem_file, dut.cache_backing_mem_i.mem);
    end
    rst_n = 1'b0;
    fetch_enable_i = 1'b0;
    irq_i = 32'h0000_0000;
    debug_halt_req = 1'b0;
    debug_resume_req = 1'b0;
    saw_debug_halted = 1'b0;
    debug_resume_armed = 1'b0;
    debug_resume_sent = 1'b0;
    reset_injected = 1'b0;
    irq_muldiv_injected = 1'b0;
    irq_muldiv_active = 1'b0;
    irq_muldiv_tail_cycles = 0;
    run_cycle = 0;
    act_tohost_value = '0;
    act_tohost_char_value = '0;
    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    fetch_enable_i = 1'b1;
    if (has_reference_output) begin
      repeat (max_cycles) begin
        @(posedge clk);
        if (dut.cache_backing_mem_i.mem[tohost_addr >> 3][(tohost_addr & 7) * 64 +: 64] !== '0) begin
          $display("TB INFO: tohost reached value=%016h", dut.cache_backing_mem_i.mem[tohost_addr >> 3][(tohost_addr & 7) * 64 +: 64]);
          break;
        end
      end
      check(dut.cache_backing_mem_i.mem[tohost_addr >> 3][(tohost_addr & 7) * 64 +: 64] !== '0,
            "tohost was not written before max_cycles expired");
    end else if (has_act_oracle) begin
      act_tohost_value = '0;
      repeat (max_cycles) begin
        @(posedge clk);
        act_tohost_value = dut.cache_backing_mem_i.mem[tohost_addr >> 3][(tohost_addr & 7) * 64 +: 64];
        if ((act_tohost_value === tohost_pass_value) ||
            (act_tohost_value === tohost_fail_value)) begin
          $display("TB INFO: ACT terminal tohost value=%016h", act_tohost_value);
          break;
        end
      end
      check((dut.cache_backing_mem_i.mem[tohost_addr >> 3][(tohost_addr & 7) * 64 +: 64] === tohost_pass_value) ||
            (dut.cache_backing_mem_i.mem[tohost_addr >> 3][(tohost_addr & 7) * 64 +: 64] === tohost_fail_value),
            "ACT terminal tohost value was not seen before max_cycles expired");
    end else begin
      completion_seen = 1'b0;
      repeat (max_cycles) begin
        @(posedge clk);
        if (has_completion &&
            (dut.riscv_core_i.id_stage_i.regfile_i.regs_q[completion_reg] === completion_value)) begin
          completion_seen = 1'b1;
          break;
        end
      end
      if (has_completion)
        check(completion_seen,
              $sformatf("completion x%0d=%016h not seen before max_cycles expired",
                        completion_reg, completion_value));
    end
    #1;
    if (has_expected_regs) begin
      compare_expected_registers(expected_regs_file);
    end
    if (has_reference_output) begin
      compare_reference_output(reference_output_file, sig_base);
    end
    if (has_fence_check) begin
      check(fence_check_seen, "FENCE did not complete before testcase end");
      $display("TB FENCE: completion observed PASS");
    end
    if (has_act_oracle) begin
      if (dut.cache_backing_mem_i.mem[tohost_addr >> 3][(tohost_addr & 7) * 64 +: 64] === tohost_fail_value) begin
        $display("TB ACT DIAG: trap_subtype=%016h trap_mode=%016h trap_actual_value=%016h trap_expected_value=%016h",
                 dut.cache_backing_mem_i.mem['h11398 >> 3]['h0],
                 dut.cache_backing_mem_i.mem['h11399 >> 3][64],
                 dut.cache_backing_mem_i.mem['h1139a >> 3][128],
                 dut.cache_backing_mem_i.mem['h1139c >> 3][256]);
        $display("TB ACT DIAG: trap_actual_offset=%016h trap_expected_offset=%016h trap_fail_str_ptr=%016h",
                 dut.cache_backing_mem_i.mem['h1139e >> 3][384],
                 dut.cache_backing_mem_i.mem['h113a0 >> 3][0],
                 dut.cache_backing_mem_i.mem['h113a2 >> 3][128]);
        $display("TB ACT DIAG: mepc=%016h mcause=%016h mtval=%016h mstatus=%016h",
                 dut.cache_backing_mem_i.mem['h113a6 >> 3][384],
                 dut.cache_backing_mem_i.mem['h113a8 >> 3][0],
                 dut.cache_backing_mem_i.mem['h113aa >> 3][128],
                 dut.cache_backing_mem_i.mem['h113ac >> 3][256]);
      end
      check(dut.cache_backing_mem_i.mem[tohost_addr >> 3][(tohost_addr & 7) * 64 +: 64] === tohost_pass_value,
            $sformatf("ACT tohost expected %016h, got %016h",
                      tohost_pass_value, dut.cache_backing_mem_i.mem[tohost_addr >> 3][(tohost_addr & 7) * 64 +: 64]));
      check(dut.cache_backing_mem_i.mem[tohost_addr >> 3][(tohost_addr & 7) * 64 +: 64] !== tohost_fail_value,
            $sformatf("ACT tohost reached fail value %016h", tohost_fail_value));
      $display("TB ACT: tohost=%016h PASS", dut.cache_backing_mem_i.mem[tohost_addr >> 3][(tohost_addr & 7) * 64 +: 64]);
    end
    if (expected_debug_cause >= 0) begin
      check(debug_cause === expected_debug_cause[2:0],
            $sformatf("debug cause expected %0d, got %0d",
                      expected_debug_cause, debug_cause));
      $display("TB DEBUG: expected cause=%0d actual=%0d PASS",
               expected_debug_cause, debug_cause);
    end
    if (debug_halt_cycle >= 0) begin
      $display("TB DEBUG: halted=%0b running=%0b mode_q=%0b halted_q=%0b pending_q=%0b resume_sent=%0b",
               debug_halted, debug_running,
               dut.riscv_core_i.debug_mode_q,
               dut.riscv_core_i.debug_halted_q,
               dut.riscv_core_i.debug_halt_pending_q,
               debug_resume_sent);
      check(saw_debug_halted || debug_resume_sent ||
            ((expected_debug_cause == 1) && debug_running && (debug_resume_cycle >= 0)),
            "external halt request never reached debug_halted state");
      $display("TB DEBUG: external halted state observed PASS");
    end
    if (reset_on_muldiv_busy != 0) begin
      check(reset_injected, "requested muldiv-busy reset was never injected");
      $display("TB RESET: muldiv-busy reset injection observed PASS");
    end
    if (irq_on_muldiv_busy != 0) begin
      check(irq_muldiv_injected, "requested muldiv-busy IRQ was never injected");
      $display("TB IRQ: muldiv-busy IRQ injection observed PASS");
    end
    $display("%s PASS: %s", TB_PHASE_NAME, tc_name);
    $finish;
  end

endmodule
