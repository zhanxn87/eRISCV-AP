// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

    task automatic run_debug_abstract_test;
    logic [31:0] data;
    logic [31:0] status;
    begin
      $display("TB DEBUG: starting Debug 1.0 minimal DMI-level abstract-command test");
      debug_dmi_begin();
      debug_dmi_write(DMI_DMCONTROL, 32'h0000_0001); // dmactive
      debug_dmi_write(DMI_DMCONTROL, 32'h8000_0001); // haltreq + dmactive
      debug_wait_halted(80);

      debug_dmi_read(DMI_DMSTATUS, status);
      check(status[3:0] == 4'h3, $sformatf("dmstatus.version expected 3, got %0h", status[3:0]));
      check(status[8] && status[9], "dmstatus does not report all/any halted");

      debug_dmi_write(DMI_COMMAND, 32'h0032_1005); // Access Register: read x5 into data0/data1.
      debug_check_cmderr_clear();
      debug_dmi_read(DMI_DATA0, data);
      check(data == 32'h1234_5678, $sformatf("abstract read x5 expected 12345678, got %08h", data));

      debug_dmi_write(DMI_DATA0, 32'hcafe_babe);
      debug_dmi_write(DMI_COMMAND, 32'h0033_1006); // Access Register: write data0/data1 into x6.
      debug_check_cmderr_clear();

      debug_dmi_write(DMI_DATA0, soc_pkg::IMEM_BASE_ADDR + 32'h0000_0008);
      debug_dmi_write(DMI_COMMAND, 32'h0033_07b1); // write dpc
      debug_check_cmderr_clear();
      debug_dmi_write(DMI_COMMAND, 32'h0032_07b1); // read dpc
      debug_check_cmderr_clear();
      debug_dmi_read(DMI_DATA0, data);
      check(data == (soc_pkg::IMEM_BASE_ADDR + 32'h0000_0008),
            $sformatf("abstract read dpc expected %08h, got %08h",
                      soc_pkg::IMEM_BASE_ADDR + 32'h0000_0008, data));

      debug_dmi_write(DMI_COMMAND, 32'h0032_07b0); // read dcsr
      debug_check_cmderr_clear();
      debug_dmi_read(DMI_DATA0, data);
      check(data[31:28] == 4'h4, $sformatf("dcsr.xdebugver expected 4, got %0h", data[31:28]));

      debug_dmi_write(DMI_DMCONTROL, 32'h4000_0001); // resumereq + dmactive
      debug_wait_running(40);
      $display("TB DEBUG: abstract-command DMI path PASS");
    end
  endtask

  task automatic run_debug_gpr_sweep_test;
    logic [31:0] data;
    logic [31:0] expected;
    logic [31:0] status;
    int reg_index;
    begin
      $display("TB DEBUG: starting full GPR abstract-access sweep");
      debug_dmi_begin();
      debug_dmi_write(DMI_DMCONTROL, 32'h0000_0001);
      debug_dmi_write(DMI_DMCONTROL, 32'h8000_0001);
      debug_wait_halted(80);
      debug_dmi_read(DMI_DMSTATUS, status);
      check(status[8] && status[9], "dmstatus does not report halted before GPR sweep");

      debug_abstract_write(16'h1000, 32'hffff_ffff);
      debug_abstract_read(16'h1000, data);
      check(data == 32'h0000_0000, $sformatf("x0 expected hardwired zero, got %08h", data));

      for (reg_index = 1; reg_index < 32; reg_index = reg_index + 1) begin
        expected = debug_gpr_pattern(reg_index);
        debug_abstract_write(16'h1000 + reg_index[15:0], expected);
        debug_abstract_read(16'h1000 + reg_index[15:0], data);
        check(data == expected,
              $sformatf("abstract GPR x%0d expected %08h, got %08h", reg_index, expected, data));
      end

      debug_dmi_write(DMI_DMCONTROL, 32'h4000_0001);
      debug_wait_running(40);
      $display("TB DEBUG: full GPR abstract-access sweep PASS");
    end
  endtask

  task automatic run_debug_completeness_test;
    logic [31:0] data;
    logic [31:0] status;
    begin
      $display("TB DEBUG: starting Debug 1.0 minimal completeness test");
      debug_dmi_begin();
      debug_dmi_write(DMI_DMCONTROL, 32'h0000_0001); // dmactive
      debug_dmi_read(DMI_DMSTATUS, status);
      check(status[3:0] == 4'h3, $sformatf("dmstatus.version expected 3, got %0h", status[3:0]));
      check(status[7] && !status[6] && !status[5], "dmstatus authentication/resethalt capability bits mismatch");
      check(status[18] && status[19], "dmstatus havereset bits were not sticky after reset");
      debug_dmi_write(DMI_DMCONTROL, 32'h1000_0001); // ackhavereset + dmactive
      debug_dmi_read(DMI_DMSTATUS, status);
      check(!status[18] && !status[19], "dmstatus havereset bits did not clear on ackhavereset");
      debug_dmi_write(DMI_DMCONTROL, 32'h03ff_ffc1); // hartsel=all ones + dmactive.
      debug_dmi_read(DMI_DMCONTROL, status);
      check(status[25:6] == 20'h0, $sformatf("single-hart hartsel should read back zero, got %05h", status[25:6]));

      debug_dmi_write(DMI_COMMAND, 32'h0032_1005); // read x5 while running: halt/resume error.
      debug_check_cmderr(3'd4);
      debug_clear_cmderr();

      debug_dmi_write(DMI_DMCONTROL, 32'h8000_0001); // haltreq + dmactive
      debug_wait_halted(80);
      debug_dmi_read(DMI_DMSTATUS, status);
      check(status[8] && status[9] && !status[10] && !status[11], "dmstatus halted/running bits mismatch while halted");

      debug_dmi_write(DMI_COMMAND, 32'h0022_1005); // unsupported RV32 aarsize.
      debug_check_cmderr(3'd2);
      debug_clear_cmderr();

      debug_dmi_write(DMI_COMMAND, 32'h0032_2000); // unsupported register number.
      debug_check_cmderr(3'd3);
      debug_clear_cmderr();

      debug_abstract_write(16'h07b2, 32'h55aa_1234);
      debug_abstract_read(16'h07b2, data);
      check(data == 32'h55aa_1234, $sformatf("dscratch0 expected 55aa1234, got %08h", data));
      debug_abstract_write(16'h07b3, 32'ha55a_4321);
      debug_abstract_read(16'h07b3, data);
      check(data == 32'ha55a_4321, $sformatf("dscratch1 expected a55a4321, got %08h", data));

      // Turn the loop body into ebreak/addi/loop while the hart is halted.
      dut.instr_mem_i.sram_i.mem[2] = 32'h0010_0073; // ebreak at PC 0x8
      dut.instr_mem_i.sram_i.mem[3] = 32'h0420_0393; // addi x7, x0, 0x42 at PC 0xc
      dut.instr_mem_i.sram_i.mem[4] = 32'h0000_006f; // loop at PC 0x10

      debug_abstract_write(16'h07b0, 32'h0000_8000); // dcsr.ebreakm=1
      debug_abstract_write(16'h07b1, soc_pkg::IMEM_BASE_ADDR + 32'h0000_0008); // dpc = ebreak
      debug_dmi_write(DMI_DMCONTROL, 32'h4000_0001); // resume into ebreak
      debug_wait_halted(80);
      debug_abstract_read(16'h07b0, data);
      check(data[8:6] == 3'd2, $sformatf("dcsr.cause after ebreak expected 2, got %0d", data[8:6]));
      debug_abstract_read(16'h07b1, data);
      check(data == (soc_pkg::IMEM_BASE_ADDR + 32'h0000_000c),
            $sformatf("dpc after ebreak expected %08h, got %08h",
                      soc_pkg::IMEM_BASE_ADDR + 32'h0000_000c, data));

      debug_abstract_write(16'h07b0, 32'h0000_0004); // dcsr.step=1, ebreakm=0
      debug_abstract_write(16'h07b1, soc_pkg::IMEM_BASE_ADDR + 32'h0000_000c); // dpc = addi x7, x0, 0x42
      debug_dmi_write(DMI_DMCONTROL, 32'h4000_0001); // resume one instruction
      debug_wait_halted(80);
      debug_abstract_read(16'h07b0, data);
      check(data[8:6] == 3'd4, $sformatf("dcsr.cause after step expected 4, got %0d", data[8:6]));
      debug_abstract_read(16'h07b1, data);
      check(data == (soc_pkg::IMEM_BASE_ADDR + 32'h0000_0010),
            $sformatf("dpc after step expected %08h, got %08h",
                      soc_pkg::IMEM_BASE_ADDR + 32'h0000_0010, data));
      debug_abstract_read(16'h1007, data);
      check(data == 32'h0000_0042, $sformatf("x7 after step expected 00000042, got %08h", data));

      debug_abstract_write(16'h07b0, 32'h0000_0000); // clear step
      debug_dmi_write(DMI_DMCONTROL, 32'h4000_0001); // final resume
      debug_wait_running(40);
      $display("TB DEBUG: completeness DMI path PASS");
    end
  endtask

  task automatic run_debug_jtag_test;
    logic [63:0] scan_out;
    logic [31:0] data;
    logic [31:0] status;
    logic [1:0]  resp;
    begin
      $display("TB DEBUG: starting JTAG DTM/DMI smoke test");
      jtag_reset_tap();

      jtag_set_ir(JTAG_IR_IDCODE);
      jtag_scan_dr(32, 64'h0, scan_out);
      check(scan_out[31:0] == 32'h1357_11db, $sformatf("JTAG IDCODE expected 135711db, got %08h", scan_out[31:0]));

      jtag_set_ir(JTAG_IR_DTMCS);
      jtag_scan_dr(32, 64'h0, scan_out);
      check(scan_out[3:0] == 4'h1, $sformatf("DTMCS version expected 1, got %0h", scan_out[3:0]));
      check(scan_out[9:4] == 6'd7, $sformatf("DTMCS abits expected 7, got %0d", scan_out[9:4]));

      jtag_set_ir(JTAG_IR_DMI);
      jtag_dmi_access(7'h7f, 32'h0000_0000, DMI_OP_READ, data, resp);
      check(resp == DMI_RESP_ERR,
            $sformatf("JTAG DMI invalid-address read returned op=%0d", resp));
      jtag_dmi_write(DMI_DMCONTROL, 32'h0000_0001);
      jtag_dmi_write(DMI_DMCONTROL, 32'h8000_0001);
      debug_wait_halted(120);
      jtag_dmi_read(DMI_DMSTATUS, status);
      check(status[3:0] == 4'h3, $sformatf("JTAG dmstatus.version expected 3, got %0h", status[3:0]));
      check(status[8] && status[9], "JTAG dmstatus does not report halted");

      jtag_dmi_write(DMI_COMMAND, 32'h0032_1005); // read x5
      jtag_check_cmderr_clear();
      jtag_dmi_read(DMI_DATA0, data);
      check(data == 32'h1234_5678, $sformatf("JTAG abstract read x5 expected 12345678, got %08h", data));

      jtag_dmi_write(DMI_DATA0, 32'hcafe_babe);
      jtag_dmi_write(DMI_COMMAND, 32'h0033_1006); // write x6
      jtag_check_cmderr_clear();

      jtag_dmi_write(DMI_DMCONTROL, 32'h4000_0001);
      debug_wait_running(80);
      $display("TB DEBUG: JTAG DTM/DMI path PASS");
    end
  endtask

  task automatic run_debug_jtag_stress_test;
    logic [63:0] scan_out;
    logic [31:0] data;
    logic [31:0] expected;
    logic [31:0] status;
    int reg_index;
    int pass_index;
    begin
      $display("TB DEBUG: starting JTAG DTM/DMI stress test");
      jtag_reset_tap();

      for (pass_index = 0; pass_index < 4; pass_index = pass_index + 1) begin
        jtag_set_ir(JTAG_IR_IDCODE);
        jtag_scan_dr(32, 64'h0, scan_out);
        check(scan_out[31:0] == 32'h1357_11db,
              $sformatf("JTAG stress IDCODE pass %0d expected 135711db, got %08h",
                        pass_index, scan_out[31:0]));
        jtag_idle(pass_index + 1);

        jtag_set_ir(JTAG_IR_DTMCS);
        jtag_scan_dr(32, 64'h0, scan_out);
        check(scan_out[3:0] == 4'h1,
              $sformatf("JTAG stress DTMCS version pass %0d expected 1, got %0h",
                        pass_index, scan_out[3:0]));
        check(scan_out[9:4] == 6'd7,
              $sformatf("JTAG stress DTMCS abits pass %0d expected 7, got %0d",
                        pass_index, scan_out[9:4]));
      end

      jtag_set_ir(JTAG_IR_DMI);
      jtag_dmi_write(DMI_DMCONTROL, 32'h0000_0001);
      jtag_dmi_write(DMI_DMCONTROL, 32'h8000_0001);
      debug_wait_halted(160);
      jtag_dmi_read(DMI_DMSTATUS, status);
      check(status[8] && status[9], "JTAG stress dmstatus does not report halted");

      jtag_abstract_write(16'h1000, 32'hffff_ffff);
      jtag_abstract_read(16'h1000, data);
      check(data == 32'h0000_0000, $sformatf("JTAG stress x0 expected zero, got %08h", data));

      for (pass_index = 0; pass_index < 2; pass_index = pass_index + 1) begin
        for (reg_index = 1; reg_index <= 8; reg_index = reg_index + 1) begin
          expected = debug_gpr_pattern(reg_index) ^ {28'h0, pass_index[3:0]};
          jtag_idle((reg_index + pass_index) % 5);
          jtag_abstract_write(16'h1000 + reg_index[15:0], expected);
          jtag_abstract_read(16'h1000 + reg_index[15:0], data);
          check(data == expected,
                $sformatf("JTAG stress x%0d pass %0d expected %08h, got %08h",
                          reg_index, pass_index, expected, data));
        end
      end

      jtag_dmi_write(DMI_DMCONTROL, 32'h4000_0001);
      debug_wait_running(100);
      $display("TB DEBUG: JTAG DTM/DMI stress path PASS");
    end
  endtask

  task automatic run_debug_openocd_like_test;
    logic [63:0] scan_out;
    logic [31:0] data;
    logic [31:0] status;
    begin
      $display("TB DEBUG: starting OpenOCD-like JTAG/DMI sequence test");
      jtag_reset_tap();

      jtag_set_ir(JTAG_IR_IDCODE);
      jtag_scan_dr(32, 64'h0, scan_out);
      check(scan_out[31:0] == 32'h1357_11db,
            $sformatf("OpenOCD-like IDCODE expected 135711db, got %08h", scan_out[31:0]));

      jtag_set_ir(JTAG_IR_DTMCS);
      jtag_scan_dr(32, 64'h0, scan_out);
      check(scan_out[3:0] == 4'h1, $sformatf("OpenOCD-like DTMCS version expected 1, got %0h", scan_out[3:0]));
      check(scan_out[9:4] == 6'd7, $sformatf("OpenOCD-like DTMCS abits expected 7, got %0d", scan_out[9:4]));

      jtag_set_ir(JTAG_IR_DMI);
      jtag_dmi_write(DMI_DMCONTROL, 32'h0000_0001);
      jtag_dmi_read(DMI_DMSTATUS, status);
      check(status[3:0] == 4'h3, $sformatf("OpenOCD-like dmstatus.version expected 3, got %0h", status[3:0]));

      jtag_dmi_write(DMI_DMCONTROL, 32'h8000_0001);
      debug_wait_halted(160);
      jtag_dmi_read(DMI_DMSTATUS, status);
      check(status[8] && status[9], "OpenOCD-like dmstatus does not report halted");

      jtag_abstract_read(16'h1005, data);
      check(data == 32'h1234_5678, $sformatf("OpenOCD-like x5 expected 12345678, got %08h", data));
      jtag_abstract_write(16'h1006, 32'h0bad_cafe);
      jtag_abstract_read(16'h1006, data);
      check(data == 32'h0bad_cafe, $sformatf("OpenOCD-like x6 expected 0badcafe, got %08h", data));

      // Patch the halted loop into ebreak/addi/loop to mimic debugger PC control.
      dut.instr_mem_i.sram_i.mem[2] = 32'h0010_0073; // ebreak at PC 0x8
      dut.instr_mem_i.sram_i.mem[3] = 32'h0420_0393; // addi x7, x0, 0x42 at PC 0xc
      dut.instr_mem_i.sram_i.mem[4] = 32'h0000_006f; // loop at PC 0x10

      jtag_abstract_write(16'h07b0, 32'h0000_8000); // dcsr.ebreakm=1
      jtag_abstract_write(16'h07b1, soc_pkg::IMEM_BASE_ADDR + 32'h0000_0008); // dpc = ebreak
      jtag_dmi_write(DMI_DMCONTROL, 32'h4000_0001);
      debug_wait_halted(160);
      jtag_abstract_read(16'h07b0, data);
      check(data[8:6] == 3'd2, $sformatf("OpenOCD-like dcsr.cause after ebreak expected 2, got %0d", data[8:6]));
      jtag_abstract_read(16'h07b1, data);
      check(data == (soc_pkg::IMEM_BASE_ADDR + 32'h0000_000c),
            $sformatf("OpenOCD-like dpc after ebreak expected %08h, got %08h",
                      soc_pkg::IMEM_BASE_ADDR + 32'h0000_000c, data));

      jtag_abstract_write(16'h07b0, 32'h0000_0004); // dcsr.step=1
      jtag_abstract_write(16'h07b1, soc_pkg::IMEM_BASE_ADDR + 32'h0000_000c); // dpc = addi x7, x0, 0x42
      jtag_dmi_write(DMI_DMCONTROL, 32'h4000_0001);
      debug_wait_halted(160);
      jtag_abstract_read(16'h07b0, data);
      check(data[8:6] == 3'd4, $sformatf("OpenOCD-like dcsr.cause after step expected 4, got %0d", data[8:6]));
      jtag_abstract_read(16'h07b1, data);
      check(data == (soc_pkg::IMEM_BASE_ADDR + 32'h0000_0010),
            $sformatf("OpenOCD-like dpc after step expected %08h, got %08h",
                      soc_pkg::IMEM_BASE_ADDR + 32'h0000_0010, data));
      jtag_abstract_read(16'h1007, data);
      check(data == 32'h0000_0042, $sformatf("OpenOCD-like x7 after step expected 00000042, got %08h", data));

      jtag_abstract_write(16'h07b0, 32'h0000_0000);
      jtag_dmi_write(DMI_DMCONTROL, 32'h4000_0001);
      debug_wait_running(100);
      $display("TB DEBUG: OpenOCD-like JTAG/DMI sequence PASS");
    end
  endtask

  task automatic run_debug_trigger_sba_test;
    logic [31:0] data;
    begin
      $display("TB DEBUG: starting trigger and SBA test");
      debug_dmi_begin();
      debug_dmi_write(DMI_DMCONTROL, 32'h0000_0001);
      debug_dmi_write(DMI_DMCONTROL, 32'h8000_0001);
      debug_wait_halted(80);

      // Trigger 0: mcontrol execute-address breakpoint at PC 0x8.
      debug_abstract_write(16'h07a0, 32'h0000_0000);
      debug_abstract_write(16'h07a1, 32'h0000_0004);
      debug_abstract_write(16'h07a2, soc_pkg::IMEM_BASE_ADDR + 32'h0000_0008);
      debug_abstract_write(16'h07b1, soc_pkg::IMEM_BASE_ADDR + 32'h0000_0008);
      debug_dmi_write(DMI_DMCONTROL, 32'h4000_0001);
      debug_wait_halted(80);
      debug_abstract_read(16'h07b0, data);
      check(data[8:6] == 3'd2, $sformatf("mcontrol cause expected 2, got %0d", data[8:6]));
      debug_abstract_read(16'h07b1, data);
      check(data == (soc_pkg::IMEM_BASE_ADDR + 32'h0000_0008),
            $sformatf("mcontrol dpc expected %08h, got %08h",
                      soc_pkg::IMEM_BASE_ADDR + 32'h0000_0008, data));

      // Trigger 0: store-address watchpoint. It must halt before DMEM changes.
      dut.instr_mem_i.sram_i.mem[2] = 32'h1100_00b7; // lui x1, 0x11000 -> DMEM base
      dut.instr_mem_i.sram_i.mem[3] = 32'h0550_0113; // addi x2, x0, 0x55
      dut.instr_mem_i.sram_i.mem[4] = 32'h0020_a023; // sw x2, 0(x1)
      dut.instr_mem_i.sram_i.mem[5] = 32'h0000_006f; // loop
      debug_abstract_write(16'h07a1, 32'h0000_0002);
      debug_abstract_write(16'h07a2, soc_pkg::DMEM_BASE_ADDR);
      debug_abstract_write(16'h07b1, soc_pkg::IMEM_BASE_ADDR + 32'h0000_0008);
      debug_dmi_write(DMI_DMCONTROL, 32'h4000_0001);
      debug_wait_halted(80);
      debug_abstract_read(16'h07b1, data);
      check(data == (soc_pkg::IMEM_BASE_ADDR + 32'h0000_0010),
            $sformatf("watchpoint dpc expected %08h, got %08h",
                      soc_pkg::IMEM_BASE_ADDR + 32'h0000_0010, data));
      check(dut.data_mem_i.sram_i.mem[0] == 32'h0000_0000,
            "watchpoint allowed the matched store to change DMEM");

      // Trigger 1: icount halts on the configured second instruction.
      debug_abstract_write(16'h07a0, 32'h0000_0000);
      debug_abstract_write(16'h07a1, 32'h0000_0000);
      debug_abstract_write(16'h07a0, 32'h0000_0001);
      debug_abstract_write(16'h07a1, 32'h3000_0002);
      debug_abstract_write(16'h07b1, soc_pkg::IMEM_BASE_ADDR + 32'h0000_0008);
      debug_dmi_write(DMI_DMCONTROL, 32'h4000_0001);
      debug_wait_halted(80);
      debug_abstract_read(16'h07b1, data);
      check(data == (soc_pkg::IMEM_BASE_ADDR + 32'h0000_000c),
            $sformatf("icount dpc expected %08h, got %08h",
                      soc_pkg::IMEM_BASE_ADDR + 32'h0000_000c, data));

      // SBA writes and reads DMEM while the hart stays halted.
      debug_dmi_write(DMI_SBADDRESS0, soc_pkg::DMEM_BASE_ADDR);
      debug_dmi_write(DMI_SBDATA0, 32'hcafe_babe);
      repeat (4) @(posedge clk);
      debug_dmi_read(DMI_SBDATA0, data); // starts SBA read; returns prior data
      repeat (4) @(posedge clk);
      debug_dmi_read(DMI_SBDATA0, data);
      check(data == 32'hcafe_babe, $sformatf("SBA readback expected cafebabe, got %08h", data));
      debug_dmi_read(DMI_SBCS, data);
      check(!data[22] && data[14:12] == 3'd0,
            $sformatf("SBA status busy/error: %08h", data));
      debug_abstract_write(16'h1006, 32'hcafe_babe);
      $display("TB DEBUG: trigger and SBA path PASS");
    end
  endtask
