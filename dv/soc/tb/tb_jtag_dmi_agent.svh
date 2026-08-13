// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

    task automatic jtag_clock(input logic tms, input logic tdi, output logic tdo);
    begin
      jtag_tms = tms;
      jtag_tdi = tdi;
      #(JTAG_TCK_QUARTER_PERIOD);
      jtag_tck = 1'b1;
      #(JTAG_TCK_QUARTER_PERIOD);
      tdo = jtag_tdo;
      #(JTAG_TCK_QUARTER_PERIOD);
      jtag_tck = 1'b0;
      #(JTAG_TCK_QUARTER_PERIOD);
    end
  endtask

  task automatic jtag_idle(input int cycles);
    logic tdo_unused;
    int cycle;
    begin
      for (cycle = 0; cycle < cycles; cycle = cycle + 1) begin
        jtag_clock(1'b0, 1'b0, tdo_unused);
      end
    end
  endtask

  task automatic jtag_reset_tap;
    logic tdo_unused;
    int cycle;
    begin
      jtag_tck = 1'b0;
      jtag_tms = 1'b1;
      jtag_tdi = 1'b0;
      jtag_trst_n = 1'b0;
      repeat (3) jtag_clock(1'b1, 1'b0, tdo_unused);
      jtag_trst_n = 1'b1;
      for (cycle = 0; cycle < 5; cycle = cycle + 1) begin
        jtag_clock(1'b1, 1'b0, tdo_unused);
      end
      jtag_clock(1'b0, 1'b0, tdo_unused);
    end
  endtask

  task automatic jtag_set_ir(input logic [JTAG_IR_WIDTH-1:0] ir_value);
    logic tdo_unused;
    int bit_index;
    begin
      jtag_clock(1'b1, 1'b0, tdo_unused); // Select-DR-Scan
      jtag_clock(1'b1, 1'b0, tdo_unused); // Select-IR-Scan
      jtag_clock(1'b0, 1'b0, tdo_unused); // Capture-IR
      jtag_clock(1'b0, 1'b0, tdo_unused); // Shift-IR
      for (bit_index = 0; bit_index < JTAG_IR_WIDTH; bit_index = bit_index + 1) begin
        jtag_clock(bit_index == (JTAG_IR_WIDTH - 1), ir_value[bit_index], tdo_unused);
      end
      jtag_clock(1'b1, 1'b0, tdo_unused); // Update-IR
      jtag_clock(1'b0, 1'b0, tdo_unused); // Run-Test/Idle
    end
  endtask

  task automatic jtag_scan_dr(input int width, input logic [63:0] scan_in, output logic [63:0] scan_out);
    logic tdo_bit;
    int bit_index;
    begin
      scan_out = 64'h0;
      jtag_clock(1'b1, 1'b0, tdo_bit); // Select-DR-Scan
      jtag_clock(1'b0, 1'b0, tdo_bit); // Capture-DR
      jtag_clock(1'b0, 1'b0, tdo_bit); // Shift-DR, exposes captured bit 0.
      scan_out[0] = tdo_bit;
      for (bit_index = 0; bit_index < width; bit_index = bit_index + 1) begin
        jtag_clock(bit_index == (width - 1), scan_in[bit_index], tdo_bit);
        if ((bit_index + 1) < width) begin
          scan_out[bit_index + 1] = tdo_bit;
        end
      end
      jtag_clock(1'b1, 1'b0, tdo_bit); // Update-DR
      jtag_clock(1'b0, 1'b0, tdo_bit); // Run-Test/Idle
    end
  endtask

  task automatic jtag_dmi_access(
    input  logic [6:0]  addr,
    input  logic [31:0] wdata,
    input  logic [1:0]  op,
    output logic [31:0] rdata,
    output logic [1:0]  resp
  );
    logic [63:0] scan_in;
    logic [63:0] scan_out;
    begin
      scan_in = {23'h0, addr, wdata, op};
      jtag_scan_dr(JTAG_DMI_SCAN_WIDTH, scan_in, scan_out);
      repeat (8) @(posedge clk);
      jtag_idle(8);
      scan_in = {23'h0, addr, 32'h0000_0000, DMI_OP_NOP};
      jtag_scan_dr(JTAG_DMI_SCAN_WIDTH, scan_in, scan_out);
      resp = scan_out[1:0];
      rdata = scan_out[33:2];
    end
  endtask

  task automatic jtag_dmi_write(input logic [6:0] addr, input logic [31:0] data);
    logic [31:0] rdata;
    logic [1:0] resp;
    begin
      jtag_dmi_access(addr, data, DMI_OP_WRITE, rdata, resp);
      check(resp == DMI_RESP_OK, $sformatf("JTAG DMI write addr=0x%02h returned op=%0d", addr, resp));
    end
  endtask

  task automatic jtag_dmi_read(input logic [6:0] addr, output logic [31:0] data);
    logic [1:0] resp;
    begin
      jtag_dmi_access(addr, 32'h0000_0000, DMI_OP_READ, data, resp);
      check(resp == DMI_RESP_OK, $sformatf("JTAG DMI read addr=0x%02h returned op=%0d", addr, resp));
    end
  endtask

  // Program loading uses the private DMI boot register window; the core stays
  // held until the final release command.
  task automatic load_instruction_memory_via_jtag_boot(input string image_file);
    localparam logic [6:0] DMI_BOOT_ADDR   = 7'h60;
    localparam logic [6:0] DMI_BOOT_WDATA  = 7'h61;
    localparam logic [6:0] DMI_BOOT_CTRL   = 7'h62;
    localparam logic [6:0] DMI_BOOT_STATUS = 7'h63;
    int file;
    int read_count;
    int status;
    int index;
    string line;
    logic [31:0] word;
    logic [31:0] data;
    begin
      file = $fopen(image_file, "r");
      if (file == 0)
        $fatal(1, "Unable to open instruction-memory file for JTAG boot: %s", image_file);

      jtag_set_ir(JTAG_IR_DMI);
      jtag_dmi_write(DMI_BOOT_CTRL, 32'h0000_000e);
      jtag_dmi_write(DMI_BOOT_ADDR, 32'h0000_0000);
      index = 0;
      read_count = $fgets(line, file);
      while (read_count != 0) begin
        status = $sscanf(line, "@%h", index);
        if (status == 1) begin
          check(index < INSTR_MEM_DEPTH, "JTAG boot instruction image address exceeds instruction memory depth");
          jtag_dmi_write(DMI_BOOT_ADDR, index);
        end else begin
          status = $sscanf(line, "%h", word);
        end
        if (status == 1 && line[0] != "@") begin
          check(index < INSTR_MEM_DEPTH, "JTAG boot instruction image exceeds instruction memory depth");
          jtag_dmi_write(DMI_BOOT_WDATA, word);
          index = index + 1;
        end else if (status != 1) begin
          $fatal(1, "Malformed instruction-memory file: %s", image_file);
        end
        read_count = $fgets(line, file);
      end
      $fclose(file);

      jtag_dmi_read(DMI_BOOT_ADDR, data);
      check(data[IMEM_WORD_ADDR_WIDTH-1:0] == index[IMEM_WORD_ADDR_WIDTH-1:0],
            $sformatf("JTAG boot addr expected %0d, got %0d", index, data[IMEM_WORD_ADDR_WIDTH-1:0]));
      jtag_dmi_write(DMI_BOOT_CTRL, 32'h0000_0005);
      jtag_dmi_read(DMI_BOOT_STATUS, data);
      check(data[1] == 1'b1, "JTAG boot status did not report fetch released");
      $display("TB JTAG BOOT: completed image through DMI; next word address=%0d", index);
    end
  endtask

  // Replay a host-generated private-DMI boot trace through the same bit-level
  // JTAG agent used by debug tests. The trace is restricted to the boot window
  // so a malformed host file cannot become arbitrary debug-register traffic.
  task automatic load_instruction_memory_via_jtag_boot_trace(input string trace_file);
    localparam logic [6:0] DMI_BOOT_ADDR   = 7'h60;
    localparam logic [6:0] DMI_BOOT_WDATA  = 7'h61;
    localparam logic [6:0] DMI_BOOT_CTRL   = 7'h62;
    localparam logic [6:0] DMI_BOOT_STATUS = 7'h63;
    int file;
    int read_count;
    int status;
    int command_count;
    int word_count;
    string line;
    logic [31:0] addr_word;
    logic [31:0] data;
    bit hold_seen;
    bit release_seen;
    begin
      file = $fopen(trace_file, "r");
      if (file == 0)
        $fatal(1, "Unable to open JTAG boot trace: %s", trace_file);

      jtag_set_ir(JTAG_IR_DMI);
      command_count = 0;
      word_count = 0;
      hold_seen = 1'b0;
      release_seen = 1'b0;
      read_count = $fgets(line, file);
      while (read_count != 0) begin
        status = $sscanf(line, "%h %h", addr_word, data);
        if (status != 2)
          $fatal(1, "Malformed JTAG boot trace line in %s: %s", trace_file, line);
        check(addr_word[31:7] == '0, "JTAG boot trace DMI address exceeds seven bits");
        check((addr_word[6:0] == DMI_BOOT_ADDR) ||
              (addr_word[6:0] == DMI_BOOT_WDATA) ||
              (addr_word[6:0] == DMI_BOOT_CTRL),
              "JTAG boot trace accesses a non-boot DMI register");
        if (addr_word[6:0] == DMI_BOOT_CTRL) begin
          if (data == 32'h0000_000e) begin
            check(!hold_seen && !release_seen, "JTAG boot trace has an invalid hold command");
            hold_seen = 1'b1;
          end else if (data == 32'h0000_0005) begin
            check(hold_seen && !release_seen, "JTAG boot trace has an invalid release command");
            release_seen = 1'b1;
          end else begin
            $fatal(1, "JTAG boot trace has an unsupported control value: %08h", data);
          end
        end else begin
          check(hold_seen && !release_seen, "JTAG boot trace write is outside the held-fetch interval");
          if (addr_word[6:0] == DMI_BOOT_WDATA)
            word_count = word_count + 1;
        end
        jtag_dmi_write(addr_word[6:0], data);
        command_count = command_count + 1;
        read_count = $fgets(line, file);
      end
      $fclose(file);

      check(hold_seen && release_seen, "JTAG boot trace did not hold and release fetch");
      jtag_dmi_read(DMI_BOOT_STATUS, data);
      check(data[1] == 1'b1, "JTAG boot trace did not release instruction fetch");
      $display("TB JTAG BOOT: replayed host trace commands=%0d words=%0d", command_count, word_count);
    end
  endtask

  task automatic jtag_check_cmderr_clear;
    logic [31:0] abstractcs;
    begin
      jtag_dmi_read(DMI_ABSTRACTCS, abstractcs);
      check(abstractcs[10:8] == 3'd0,
            $sformatf("JTAG abstractcs.cmderr expected 0, got %0d", abstractcs[10:8]));
    end
  endtask

  task automatic jtag_abstract_read(input logic [15:0] regno, output logic [63:0] data);
    logic [31:0] data0;
    logic [31:0] data1;
    begin
      jtag_dmi_write(DMI_COMMAND, 32'h0032_0000 | {16'h0000, regno});
      jtag_check_cmderr_clear();
      jtag_dmi_read(DMI_DATA0, data0);
      jtag_dmi_read(DMI_DATA1, data1);
      data = {data1, data0};
    end
  endtask

  task automatic jtag_abstract_write(input logic [15:0] regno, input logic [63:0] data);
    begin
      jtag_dmi_write(DMI_DATA0, data[31:0]);
      jtag_dmi_write(DMI_DATA1, data[63:32]);
      jtag_dmi_write(DMI_COMMAND, 32'h0033_0000 | {16'h0000, regno});
      jtag_check_cmderr_clear();
    end
  endtask
