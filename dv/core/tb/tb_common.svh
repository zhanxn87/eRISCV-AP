// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

  // Shared oracle helpers for register, memory-signature, and trace checks.
  task automatic check(input bit condition, input string message);
    if (!condition) begin
      $display("%s FAIL: %s", TB_PHASE_NAME, message);
      $fatal(1);
    end
  endtask

  task automatic compare_expected_registers(input string expected_file);
    int file;
    int status;
    int reg_index;
    int checked;
    xlen_t expected_value;
    xlen_t actual_value;
    begin
      file = $fopen(expected_file, "r");
      if (file == 0) begin
        $fatal(1, "Unable to open expected-register file: %s", expected_file);
      end

      checked = 0;
      while (!$feof(file)) begin
        status = $fscanf(file, "%d %h\n", reg_index, expected_value);
        if (status == 2) begin
          check(reg_index >= 0 && reg_index < 32, "expected-register index is out of range");
          actual_value = dut.riscv_core_i.id_stage_i.regfile_i.regs_q[reg_index];
          check(actual_value === expected_value,
                $sformatf("x%0d expected %016h, got %016h", reg_index, expected_value, actual_value));
          $display("TB CHECK: x%0d expected=%016h actual=%016h PASS",
                   reg_index, expected_value, actual_value);
          checked = checked + 1;
        end else if (!$feof(file)) begin
          $fatal(1, "Malformed expected-register file: %s", expected_file);
        end
      end
      $fclose(file);
      check(checked != 0, "expected-register file must contain at least one check");
      $display("TB CHECK: %0d expected-register comparisons PASS", checked);
    end
  endtask

  task automatic compare_reference_output(input string ref_file, input int unsigned base);
    int file;
    int status;
    int index;
    int checked;
    logic [63:0] expected_value;
    logic [63:0] actual_value;
    begin
      file = $fopen(ref_file, "r");
      if (file == 0) begin
        $fatal(1, "Unable to open reference-output file: %s", ref_file);
      end

      index = 0;
      checked = 0;
      while (!$feof(file)) begin
        status = $fscanf(file, "%h\n", expected_value);
        if (status == 1) begin
          actual_value = dut.data_mem_i.sram_i.mem[base + index];
          check(actual_value === expected_value,
                $sformatf("signature[%0d] doubleword=%08h expected %016h, got %016h",
                          index, base + index, expected_value, actual_value));
          $display("TB SIGNATURE: index=%0d doubleword=%08h expected=%016h actual=%016h PASS",
                   index, base + index, expected_value, actual_value);
          checked = checked + 1;
        end else if (!$feof(file)) begin
          $fatal(1, "Malformed reference-output file: %s", ref_file);
        end
        index = index + 1;
      end

      $fclose(file);
      check(checked != 0, "reference-output file must contain at least one check");
      $display("TB CHECK: %0d signature comparisons PASS", checked);
    end
  endtask

  task automatic init_instruction_memory(input logic [31:0] fill_value);
    int index;
    begin
      for (index = 0; index < INSTR_MEM_DEPTH; index = index + 1) begin
        dut.instr_mem_i.sram_i.mem[index] = fill_value;
      end
    end
  endtask

  task automatic init_data_memory(input logic [63:0] fill_value);
    int index;
    begin
      for (index = 0; index < DATA_MEM_DEPTH; index = index + 1) begin
        dut.data_mem_i.sram_i.mem[index] = fill_value;
      end
    end
  endtask
