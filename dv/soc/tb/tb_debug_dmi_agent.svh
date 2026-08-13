// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

  // Direct-DMI scenarios use the architectural JTAG DTM/DMI transport.  This
  // keeps the agent portable across simulators and avoids hierarchy force.
  task automatic debug_dmi_begin;
    begin
      jtag_reset_tap();
      jtag_set_ir(JTAG_IR_DMI);
    end
  endtask

  task automatic debug_dmi_access(
    input  logic [6:0]  addr,
    input  logic [31:0] wdata,
    input  logic [1:0]  op,
    output logic [31:0] rdata,
    output logic [1:0]  resp
  );
    begin
      jtag_dmi_access(addr, wdata, op, rdata, resp);
    end
  endtask

  task automatic debug_dmi_write(input logic [6:0] addr, input logic [31:0] data);
    logic [31:0] rdata;
    logic [1:0]  resp;
    begin
      debug_dmi_access(addr, data, DMI_OP_WRITE, rdata, resp);
      check(resp == DMI_RESP_OK, $sformatf("DMI write addr=0x%02h returned op=%0d", addr, resp));
    end
  endtask

  task automatic debug_dmi_read(input logic [6:0] addr, output logic [31:0] data);
    logic [1:0] resp;
    begin
      debug_dmi_access(addr, 32'h0000_0000, DMI_OP_READ, data, resp);
      check(resp == DMI_RESP_OK, $sformatf("DMI read addr=0x%02h returned op=%0d", addr, resp));
    end
  endtask

  task automatic debug_wait_halted(input int timeout_cycles);
    bit seen;
    int cycle;
    begin
      seen = 1'b0;
      for (cycle = 0; cycle < timeout_cycles; cycle = cycle + 1) begin
        @(posedge clk);
        #1;
        if (debug_halted) begin
          seen = 1'b1;
          break;
        end
      end
      check(seen, "debug halt request did not halt the hart");
      $display("TB DEBUG: hart halted pc=%016h cause=%0d", debug_pc, debug_cause);
    end
  endtask

  task automatic debug_wait_running(input int timeout_cycles);
    bit seen;
    int cycle;
    begin
      seen = 1'b0;
      for (cycle = 0; cycle < timeout_cycles; cycle = cycle + 1) begin
        @(posedge clk);
        #1;
        if (debug_running && !debug_halted) begin
          seen = 1'b1;
          break;
        end
      end
      check(seen, "debug resume request did not return the hart to running state");
      $display("TB DEBUG: hart resumed pc=%016h", debug_pc);
    end
  endtask

  task automatic debug_check_cmderr(input logic [2:0] expected_cmderr);
    logic [31:0] abstractcs;
    begin
      debug_dmi_read(DMI_ABSTRACTCS, abstractcs);
      check(abstractcs[10:8] == expected_cmderr,
            $sformatf("abstractcs.cmderr expected %0d, got %0d", expected_cmderr, abstractcs[10:8]));
    end
  endtask

  task automatic debug_check_cmderr_clear;
    begin
      debug_check_cmderr(3'd0);
    end
  endtask

  task automatic debug_clear_cmderr;
    begin
      debug_dmi_write(DMI_ABSTRACTCS, 32'h0000_0700);
      debug_check_cmderr_clear();
    end
  endtask

  task automatic debug_abstract_read(input logic [15:0] regno, output logic [63:0] data);
    logic [31:0] data0;
    logic [31:0] data1;
    begin
      debug_dmi_write(DMI_COMMAND, 32'h0032_0000 | {16'h0000, regno});
      debug_check_cmderr_clear();
      debug_dmi_read(DMI_DATA0, data0);
      debug_dmi_read(DMI_DATA1, data1);
      data = {data1, data0};
    end
  endtask

  task automatic debug_abstract_write(input logic [15:0] regno, input logic [63:0] data);
    begin
      debug_dmi_write(DMI_DATA0, data[31:0]);
      debug_dmi_write(DMI_DATA1, data[63:32]);
      debug_dmi_write(DMI_COMMAND, 32'h0033_0000 | {16'h0000, regno});
      debug_check_cmderr_clear();
    end
  endtask

  function automatic logic [63:0] debug_gpr_pattern(input int reg_index);
    begin
      debug_gpr_pattern = 64'h5a5a_1000_a5a5_0000 ^
                          (64'(reg_index) * 64'h0101_0101_0101_0101);
    end
  endfunction
