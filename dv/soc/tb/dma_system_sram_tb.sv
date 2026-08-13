// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

module dma_system_sram_tb #(
  parameter int SYS_SRAM_LOAD_BYPASS_P = 0
);
  import soc_pkg::*;

  logic clk, rst_n;
  logic cfg_req, cfg_we, cfg_resp, cfg_err;
  logic [31:0] cfg_addr, cfg_wdata, cfg_rdata;
  logic dma_req_valid, dma_req_we, dma_req_ready, dma_resp_valid, dma_resp_err, dma_irq;
  logic [3:0] dma_req_be;
  logic [31:0] dma_req_addr, dma_req_wdata, dma_resp_rdata;
  logic fabric_dma_resp_valid, fabric_dma_resp_err, force_dma_resp_err;
  logic [31:0] fabric_dma_resp_rdata;
  logic cpu_req_valid, cpu_req_we, cpu_req_ready, cpu_resp_valid, cpu_resp_err;
  logic [3:0] cpu_req_be;
  logic [31:0] cpu_req_addr, cpu_req_wdata, cpu_resp_rdata;
  logic [31:0] status;
  logic saw_same_bank_contention;
  int same_bank_cpu_responses;
  int errors;
  int cycles;
  localparam int LAST_BANK_WORD = (1 << SYSTEM_SRAM_BANK_WORD_ADDR_WIDTH) - 1;

  dma_controller dma_i (
    .clk, .rst_n,
    .cfg_req_i(cfg_req), .cfg_we_i(cfg_we), .cfg_addr_i(cfg_addr), .cfg_wdata_i(cfg_wdata),
    .cfg_resp_valid_o(cfg_resp), .cfg_rdata_o(cfg_rdata), .cfg_err_o(cfg_err),
    .dma_req_valid_o(dma_req_valid), .dma_req_we_o(dma_req_we), .dma_req_be_o(dma_req_be),
    .dma_req_addr_o(dma_req_addr), .dma_req_wdata_o(dma_req_wdata),
    .dma_req_ready_i(dma_req_ready), .dma_resp_valid_i(dma_resp_valid),
    .dma_resp_rdata_i(dma_resp_rdata), .dma_resp_err_i(dma_resp_err),
    .uart_tx_valid_o(), .uart_tx_data_o(), .uart_tx_ready_i(1'b0), .irq_o(dma_irq)
  );

  system_sram_fabric #(
    .SYS_SRAM_LOAD_BYPASS_P(SYS_SRAM_LOAD_BYPASS_P != 0)
  ) system_sram_fabric_i (
    .clk, .rst_n,
    .cpu_req_valid_i(cpu_req_valid), .cpu_req_we_i(cpu_req_we), .cpu_req_be_i(cpu_req_be),
    .cpu_req_addr_i(cpu_req_addr), .cpu_req_wdata_i(cpu_req_wdata), .cpu_req_ready_o(cpu_req_ready),
    .cpu_resp_valid_o(cpu_resp_valid), .cpu_resp_rdata_o(cpu_resp_rdata), .cpu_resp_err_o(cpu_resp_err),
    .dma_req_valid_i(dma_req_valid), .dma_req_we_i(dma_req_we), .dma_req_be_i(dma_req_be),
    .dma_req_addr_i(dma_req_addr), .dma_req_wdata_i(dma_req_wdata), .dma_req_ready_o(dma_req_ready),
    .dma_resp_valid_o(fabric_dma_resp_valid), .dma_resp_rdata_o(fabric_dma_resp_rdata),
    .dma_resp_err_o(fabric_dma_resp_err)
  );

  assign dma_resp_valid = fabric_dma_resp_valid;
  assign dma_resp_rdata = fabric_dma_resp_rdata;
  assign dma_resp_err = fabric_dma_resp_err ||
                        (force_dma_resp_err && dma_system_sram_tb.dma_i.state_q == 4'd4);

  initial clk = 1'b0;
  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (rst_n && cpu_req_valid && dma_req_valid &&
        (cpu_req_addr[4:2] == dma_req_addr[4:2]))
      saw_same_bank_contention <= 1'b1;
    if (rst_n && cpu_resp_valid)
      same_bank_cpu_responses <= same_bank_cpu_responses + 1;
  end

  task automatic check(input logic condition, input string message);
    if (!condition) begin
      errors = errors + 1;
      $display("DMA SYSTEM SRAM FAIL: %s", message);
    end
  endtask

  task automatic cfg_write(input logic [5:0] offset, input logic [31:0] value);
    begin
      @(negedge clk);
      cfg_req = 1'b1;
      cfg_we = 1'b1;
      cfg_addr = DMA_BASE_ADDR + {{26{1'b0}}, offset};
      cfg_wdata = value;
      while (!cfg_resp) @(negedge clk);
      #1 check(!cfg_err, "configuration write response");
      cfg_req = 1'b0;
      cfg_we = 1'b0;
    end
  endtask

  task automatic cfg_read(input logic [5:0] offset, output logic [31:0] value);
    begin
      @(negedge clk);
      cfg_req = 1'b1;
      cfg_we = 1'b0;
      cfg_addr = DMA_BASE_ADDR + {{26{1'b0}}, offset};
      while (!cfg_resp) @(negedge clk);
      #1 check(!cfg_err, "configuration read response");
      value = cfg_rdata;
      cfg_req = 1'b0;
    end
  endtask

  task automatic wait_irq;
    begin
      cycles = 0;
      while (!dma_irq && (cycles < 80)) begin
        @(posedge clk);
        cycles = cycles + 1;
      end
      check(dma_irq, "DMA interrupt timeout");
    end
  endtask

  task automatic wait_idle;
    begin
      cycles = 0;
      while (dma_system_sram_tb.dma_i.state_q != 4'd0 && (cycles < 500)) begin
        @(posedge clk);
        cycles = cycles + 1;
      end
      check(dma_system_sram_tb.dma_i.state_q == 4'd0, "DMA completion timeout");
    end
  endtask

  task automatic wait_idle_long;
    begin
      cycles = 0;
      while (dma_system_sram_tb.dma_i.state_q != 4'd0 && (cycles < 20000)) begin
        @(posedge clk);
        cycles = cycles + 1;
      end
      check(dma_system_sram_tb.dma_i.state_q == 4'd0, "long DMA completion timeout");
    end
  endtask

  task automatic wait_dma_state(input logic [3:0] expected_state);
    begin
      cycles = 0;
      while (dma_system_sram_tb.dma_i.state_q != expected_state && (cycles < 100)) begin
        @(negedge clk);
        cycles = cycles + 1;
      end
      check(dma_system_sram_tb.dma_i.state_q == expected_state, "DMA state timeout");
    end
  endtask

  task automatic wait_cpu_response;
    begin
      cycles = 0;
      while (!cpu_resp_valid && (cycles < 20)) begin
        @(posedge clk);
        cycles = cycles + 1;
      end
      check(cpu_resp_valid && !cpu_resp_err, "CPU System SRAM response timeout");
    end
  endtask

  task automatic cpu_read(input logic [31:0] address,
                          input logic [31:0] expected_data);
    begin
      @(negedge clk);
      cpu_req_valid = 1'b1;
      cpu_req_we = 1'b0;
      cpu_req_be = 4'hf;
      cpu_req_addr = address;
      while (!cpu_req_ready) @(negedge clk);
      @(negedge clk);
      cpu_req_valid = 1'b0;
      wait_cpu_response();
      #1 check(cpu_resp_rdata == expected_data, "CPU System SRAM load data");
    end
  endtask

  initial begin
    rst_n = 1'b0;
    cfg_req = 1'b0; cfg_we = 1'b0; cfg_addr = '0; cfg_wdata = '0;
    cpu_req_valid = 1'b0; cpu_req_we = 1'b0; cpu_req_be = '0; cpu_req_addr = '0; cpu_req_wdata = '0;
    errors = 0;
    saw_same_bank_contention = 1'b0;
    same_bank_cpu_responses = 0;
    force_dma_resp_err = 1'b0;
    system_sram_fabric_i.gen_bank[0].system_sram_i.sram_i.mem[0] = 32'h1122_3344;
    system_sram_fabric_i.gen_bank[1].system_sram_i.sram_i.mem[0] = 32'h5566_7788;
    system_sram_fabric_i.gen_bank[4].system_sram_i.sram_i.mem[0] = 32'h0000_0000;
    system_sram_fabric_i.gen_bank[5].system_sram_i.sram_i.mem[0] = 32'h0000_0000;
    system_sram_fabric_i.gen_bank[3].system_sram_i.sram_i.mem[0] = 32'h0000_0000;
    system_sram_fabric_i.gen_bank[7].system_sram_i.sram_i.mem[LAST_BANK_WORD] = 32'hdead_beef;
    system_sram_fabric_i.gen_bank[0].system_sram_i.sram_i.mem[1] = 32'h0000_0000;
    system_sram_fabric_i.gen_bank[1].system_sram_i.sram_i.mem[1] = 32'h0000_0000;
    system_sram_fabric_i.gen_bank[0].system_sram_i.sram_i.mem[32] = 32'hb16b_00b5;
    system_sram_fabric_i.gen_bank[0].system_sram_i.sram_i.mem[40] = 32'h0000_0000;
    system_sram_fabric_i.gen_bank[0].system_sram_i.sram_i.mem[48] = 32'h1234_5678;
    // Two linked 32-byte descriptors at 0x80 and 0xa0.  Descriptor words are
    // interleaved over the System SRAM banks, so each word has the same index.
    system_sram_fabric_i.gen_bank[0].system_sram_i.sram_i.mem[4] = SYSTEM_SRAM_BASE_ADDR + 32'h0000_00a0;
    system_sram_fabric_i.gen_bank[1].system_sram_i.sram_i.mem[4] = SYSTEM_SRAM_BASE_ADDR + 32'h0000_0100;
    system_sram_fabric_i.gen_bank[2].system_sram_i.sram_i.mem[4] = SYSTEM_SRAM_BASE_ADDR + 32'h0000_0200;
    system_sram_fabric_i.gen_bank[3].system_sram_i.sram_i.mem[4] = 32'd4;
    system_sram_fabric_i.gen_bank[4].system_sram_i.sram_i.mem[4] = 32'h0000_0019;
    system_sram_fabric_i.gen_bank[5].system_sram_i.sram_i.mem[4] = 32'd0;
    system_sram_fabric_i.gen_bank[6].system_sram_i.sram_i.mem[4] = 32'd0;
    system_sram_fabric_i.gen_bank[0].system_sram_i.sram_i.mem[5] = 32'd0;
    system_sram_fabric_i.gen_bank[1].system_sram_i.sram_i.mem[5] = SYSTEM_SRAM_BASE_ADDR + 32'h0000_0104;
    system_sram_fabric_i.gen_bank[2].system_sram_i.sram_i.mem[5] = SYSTEM_SRAM_BASE_ADDR + 32'h0000_0204;
    system_sram_fabric_i.gen_bank[3].system_sram_i.sram_i.mem[5] = 32'd4;
    system_sram_fabric_i.gen_bank[4].system_sram_i.sram_i.mem[5] = 32'h0000_001f;
    system_sram_fabric_i.gen_bank[5].system_sram_i.sram_i.mem[5] = 32'd0;
    system_sram_fabric_i.gen_bank[6].system_sram_i.sram_i.mem[5] = 32'd0;
    system_sram_fabric_i.gen_bank[0].system_sram_i.sram_i.mem[8] = 32'hc001_cafe;
    system_sram_fabric_i.gen_bank[1].system_sram_i.sram_i.mem[8] = 32'hf00d_face;
    system_sram_fabric_i.gen_bank[0].system_sram_i.sram_i.mem[16] = 32'd0;
    system_sram_fabric_i.gen_bank[1].system_sram_i.sram_i.mem[16] = 32'd0;
    repeat (2) @(posedge clk);
    rst_n = 1'b1;

    cfg_write(6'h08, SYSTEM_SRAM_BASE_ADDR);
    cfg_write(6'h0c, SYSTEM_SRAM_BASE_ADDR + 32'h10);
    cfg_write(6'h10, 32'd8);
    cfg_write(6'h00, 32'h0000_0003);
    cpu_req_valid = 1'b1;
    cpu_req_we = 1'b1;
    cpu_req_be = 4'hf;
    cpu_req_addr = SYSTEM_SRAM_BASE_ADDR + 32'h0000_000c;
    cpu_req_wdata = 32'ha5a5_5a5a;
    #1 check(cpu_req_ready && dma_req_ready,
             "different-bank CPU and DMA requests must be accepted concurrently");
    @(negedge clk);
    cpu_req_valid = 1'b0;
    cpu_req_we = 1'b0;
    wait_cpu_response();
    wait_irq();
    check(system_sram_fabric_i.gen_bank[4].system_sram_i.sram_i.mem[0] == 32'h1122_3344,
          "first copied word");
    check(system_sram_fabric_i.gen_bank[5].system_sram_i.sram_i.mem[0] == 32'h5566_7788,
          "second copied word");
    check(system_sram_fabric_i.gen_bank[3].system_sram_i.sram_i.mem[0] == 32'ha5a5_5a5a,
          "CPU write through bank 3");
    cfg_read(6'h04, status);
    check(status[2:0] == 3'b010, "DONE must be sticky after a successful transfer");

    // Keep CPU requests asserted while the DMA reads and writes bank 0. The
    // registered round-robin arbiter must admit both masters without loss.
    cfg_write(6'h04, 32'h0000_0002);
    saw_same_bank_contention = 1'b0;
    same_bank_cpu_responses = 0;
    @(negedge clk);
    cpu_req_valid = 1'b1;
    cpu_req_we = 1'b1;
    cpu_req_be = 4'hf;
    cpu_req_addr = SYSTEM_SRAM_BASE_ADDR + 32'h0000_0600;
    cpu_req_wdata = 32'hfeed_c0de;
    cfg_write(6'h08, SYSTEM_SRAM_BASE_ADDR + 32'h0000_0400);
    cfg_write(6'h0c, SYSTEM_SRAM_BASE_ADDR + 32'h0000_0500);
    cfg_write(6'h10, 32'd4);
    cfg_write(6'h00, 32'h0000_0003);
    wait_irq();
    @(negedge clk);
    cpu_req_valid = 1'b0;
    cpu_req_we = 1'b0;
    check(saw_same_bank_contention, "same-bank CPU/DMA requests must overlap");
    check(same_bank_cpu_responses != 0, "same-bank CPU request stream must make progress");
    check(system_sram_fabric_i.gen_bank[0].system_sram_i.sram_i.mem[48] == 32'hfeed_c0de,
          "same-bank CPU write data must remain intact");
    check(system_sram_fabric_i.gen_bank[0].system_sram_i.sram_i.mem[40] == 32'hb16b_00b5,
          "same-bank DMA copy must complete without loss");

    cfg_write(6'h04, 32'h0000_0002);
    cfg_write(6'h08, IMEM_BASE_ADDR);
    cfg_write(6'h0c, SYSTEM_SRAM_BASE_ADDR + 32'h20);
    cfg_write(6'h10, 32'd4);
    cfg_write(6'h00, 32'h0000_0003);
    wait_irq();
    cfg_read(6'h04, status);
    check(status[2:0] == 3'b100, "firewall denial must set ERROR only");
    check(system_sram_fabric_i.gen_bank[0].system_sram_i.sram_i.mem[1] == 32'h0000_0000,
          "denied transfer must not write System SRAM");

    cfg_write(6'h04, 32'h0000_0006);
    cfg_write(6'h08, SYSTEM_SRAM_LIMIT_ADDR - 32'd4);
    cfg_write(6'h0c, SYSTEM_SRAM_BASE_ADDR + 32'h20);
    cfg_write(6'h10, 32'd4);
    cfg_write(6'h00, 32'h0000_0003);
    wait_irq();
    cfg_read(6'h04, status);
    check(status[2:0] == 3'b010, "last System SRAM word transfer must complete");
    check(system_sram_fabric_i.gen_bank[0].system_sram_i.sram_i.mem[1] == 32'hdead_beef,
          "last System SRAM word must copy");

    cfg_write(6'h04, 32'h0000_0006);
    cfg_write(6'h08, SYSTEM_SRAM_LIMIT_ADDR - 32'd4);
    cfg_write(6'h0c, SYSTEM_SRAM_BASE_ADDR + 32'h24);
    cfg_write(6'h10, 32'd8);
    cfg_write(6'h00, 32'h0000_0003);
    wait_irq();
    cfg_read(6'h04, status);
    check(status[2:0] == 3'b100, "out-of-range length must set ERROR only");
    check(system_sram_fabric_i.gen_bank[1].system_sram_i.sram_i.mem[1] == 32'h0000_0000,
          "out-of-range transfer must not write its first destination word");

    cfg_write(6'h04, 32'h0000_000e);
    cfg_write(6'h14, SYSTEM_SRAM_BASE_ADDR + 32'h80);
    cfg_write(6'h00, 32'h0000_000a);
    wait_idle();
    check(dma_irq, "descriptor terminal completion must raise DMA IRQ");
    cfg_read(6'h04, status);
    check(status[3:0] == 4'b1010, "descriptor chain must report DONE and descriptor IRQ");
    check(system_sram_fabric_i.gen_bank[0].system_sram_i.sram_i.mem[16] == 32'hc001_cafe,
          "first descriptor copied word");
    check(system_sram_fabric_i.gen_bank[1].system_sram_i.sram_i.mem[16] == 32'hf00d_face,
          "second descriptor copied word");
    check(system_sram_fabric_i.gen_bank[4].system_sram_i.sram_i.mem[4] == 32'h0000_0018,
          "first descriptor OWN must clear");
    check(system_sram_fabric_i.gen_bank[5].system_sram_i.sram_i.mem[4] == 32'h0000_0001 &&
          system_sram_fabric_i.gen_bank[6].system_sram_i.sram_i.mem[4] == 32'd4,
          "first descriptor must report DONE and bytes transferred");
    check(system_sram_fabric_i.gen_bank[4].system_sram_i.sram_i.mem[5] == 32'h0000_001e,
          "terminal descriptor OWN must clear");
    check(system_sram_fabric_i.gen_bank[5].system_sram_i.sram_i.mem[5] == 32'h0000_0001 &&
          system_sram_fabric_i.gen_bank[6].system_sram_i.sram_i.mem[5] == 32'd4,
          "terminal descriptor must report DONE and bytes transferred");

    cfg_write(6'h04, 32'h0000_000e);
    system_sram_fabric_i.gen_bank[5].system_sram_i.sram_i.mem[4] = 32'ha5a5_a5a5;
    cfg_write(6'h14, SYSTEM_SRAM_BASE_ADDR + 32'h80);
    cfg_write(6'h00, 32'h0000_000a);
    wait_idle();
    cfg_read(6'h04, status);
    check(status[2:0] == 3'b100, "unowned descriptor must set channel ERROR");
    check(system_sram_fabric_i.gen_bank[4].system_sram_i.sram_i.mem[4] == 32'h0000_0018 &&
          system_sram_fabric_i.gen_bank[5].system_sram_i.sram_i.mem[4] == 32'ha5a5_a5a5,
          "unowned descriptor must remain untouched");

    // An owned malformed descriptor is completed with descriptor ERROR.
    cfg_write(6'h04, 32'h0000_000e);
    system_sram_fabric_i.gen_bank[0].system_sram_i.sram_i.mem[4] = 32'd0;
    system_sram_fabric_i.gen_bank[1].system_sram_i.sram_i.mem[4] = SYSTEM_SRAM_BASE_ADDR + 32'h100;
    system_sram_fabric_i.gen_bank[2].system_sram_i.sram_i.mem[4] = SYSTEM_SRAM_BASE_ADDR + 32'h200;
    system_sram_fabric_i.gen_bank[3].system_sram_i.sram_i.mem[4] = 32'd4;
    system_sram_fabric_i.gen_bank[4].system_sram_i.sram_i.mem[4] = 32'h0000_0015;
    system_sram_fabric_i.gen_bank[5].system_sram_i.sram_i.mem[4] = 32'd0;
    system_sram_fabric_i.gen_bank[6].system_sram_i.sram_i.mem[4] = 32'd0;
    cfg_write(6'h14, SYSTEM_SRAM_BASE_ADDR + 32'h80);
    cfg_write(6'h00, 32'h0000_000a);
    wait_idle();
    cfg_read(6'h04, status);
    check(status[2:0] == 3'b100, "malformed descriptor must set channel ERROR");
    check(system_sram_fabric_i.gen_bank[4].system_sram_i.sram_i.mem[4] == 32'h0000_0014 &&
          system_sram_fabric_i.gen_bank[5].system_sram_i.sram_i.mem[4] == 32'h0000_0002 &&
          system_sram_fabric_i.gen_bank[6].system_sram_i.sram_i.mem[4] == 32'd0,
          "malformed owned descriptor must receive ERROR writeback");

    // A payload bus error still clears OWN and reports transferred bytes.
    cfg_write(6'h04, 32'h0000_000e);
    system_sram_fabric_i.gen_bank[0].system_sram_i.sram_i.mem[4] = 32'd0;
    system_sram_fabric_i.gen_bank[1].system_sram_i.sram_i.mem[4] = SYSTEM_SRAM_BASE_ADDR + 32'h100;
    system_sram_fabric_i.gen_bank[2].system_sram_i.sram_i.mem[4] = SYSTEM_SRAM_BASE_ADDR + 32'h200;
    system_sram_fabric_i.gen_bank[3].system_sram_i.sram_i.mem[4] = 32'd4;
    system_sram_fabric_i.gen_bank[4].system_sram_i.sram_i.mem[4] = 32'h0000_001d;
    system_sram_fabric_i.gen_bank[5].system_sram_i.sram_i.mem[4] = 32'd0;
    system_sram_fabric_i.gen_bank[6].system_sram_i.sram_i.mem[4] = 32'd0;
    force_dma_resp_err = 1'b1;
    cfg_write(6'h14, SYSTEM_SRAM_BASE_ADDR + 32'h80);
    cfg_write(6'h00, 32'h0000_000a);
    wait_idle();
    force_dma_resp_err = 1'b0;
    cfg_read(6'h04, status);
    check(status[2:0] == 3'b100, "payload bus error must set channel ERROR");
    check(system_sram_fabric_i.gen_bank[4].system_sram_i.sram_i.mem[4] == 32'h0000_001c &&
          system_sram_fabric_i.gen_bank[5].system_sram_i.sram_i.mem[4] == 32'h0000_0002 &&
          system_sram_fabric_i.gen_bank[6].system_sram_i.sram_i.mem[4] == 32'd0,
          "payload bus error must receive descriptor ERROR writeback");

    // Abort an owned multiword descriptor after it starts; OWN must clear and
    // bytes_transferred must describe only writes accepted before the abort.
    cfg_write(6'h04, 32'h0000_000e);
    system_sram_fabric_i.gen_bank[0].system_sram_i.sram_i.mem[4] = 32'd0;
    system_sram_fabric_i.gen_bank[1].system_sram_i.sram_i.mem[4] = SYSTEM_SRAM_BASE_ADDR + 32'h100;
    system_sram_fabric_i.gen_bank[2].system_sram_i.sram_i.mem[4] = SYSTEM_SRAM_BASE_ADDR + 32'h200;
    system_sram_fabric_i.gen_bank[3].system_sram_i.sram_i.mem[4] = 32'd64;
    system_sram_fabric_i.gen_bank[4].system_sram_i.sram_i.mem[4] = 32'h0000_001d;
    system_sram_fabric_i.gen_bank[5].system_sram_i.sram_i.mem[4] = 32'd0;
    system_sram_fabric_i.gen_bank[6].system_sram_i.sram_i.mem[4] = 32'd0;
    cfg_write(6'h14, SYSTEM_SRAM_BASE_ADDR + 32'h80);
    cfg_write(6'h00, 32'h0000_000a);
    wait_dma_state(4'd5);
    cfg_write(6'h00, 32'h0000_0006);
    wait_idle();
    cfg_read(6'h04, status);
    check(status[2:0] == 3'b100, "descriptor abort must set channel ERROR");
    check(system_sram_fabric_i.gen_bank[4].system_sram_i.sram_i.mem[4] == 32'h0000_001c &&
          system_sram_fabric_i.gen_bank[5].system_sram_i.sram_i.mem[4] == 32'h0000_0002 &&
          system_sram_fabric_i.gen_bank[6].system_sram_i.sram_i.mem[4] < 32'd64,
          "descriptor abort must clear OWN and write partial byte count");

    // A loop revisits an unowned completed descriptor and must terminate.
    cfg_write(6'h04, 32'h0000_000e);
    system_sram_fabric_i.gen_bank[0].system_sram_i.sram_i.mem[4] = SYSTEM_SRAM_BASE_ADDR + 32'h80;
    system_sram_fabric_i.gen_bank[1].system_sram_i.sram_i.mem[4] = SYSTEM_SRAM_BASE_ADDR + 32'h100;
    system_sram_fabric_i.gen_bank[2].system_sram_i.sram_i.mem[4] = SYSTEM_SRAM_BASE_ADDR + 32'h200;
    system_sram_fabric_i.gen_bank[3].system_sram_i.sram_i.mem[4] = 32'd4;
    system_sram_fabric_i.gen_bank[4].system_sram_i.sram_i.mem[4] = 32'h0000_0019;
    system_sram_fabric_i.gen_bank[5].system_sram_i.sram_i.mem[4] = 32'd0;
    system_sram_fabric_i.gen_bank[6].system_sram_i.sram_i.mem[4] = 32'd0;
    cfg_write(6'h14, SYSTEM_SRAM_BASE_ADDR + 32'h80);
    cfg_write(6'h00, 32'h0000_000a);
    wait_idle();
    cfg_read(6'h04, status);
    check(status[2:0] == 3'b100, "descriptor loop must terminate with channel ERROR");
    check(system_sram_fabric_i.gen_bank[4].system_sram_i.sram_i.mem[4] == 32'h0000_0018 &&
          system_sram_fabric_i.gen_bank[5].system_sram_i.sram_i.mem[4] == 32'h0000_0001,
          "loop revisit must not modify the completed unowned descriptor");

    // 257 linked descriptors exercise the 256-descriptor chain bound.
    for (int descriptor_index = 0; descriptor_index <= 256; descriptor_index = descriptor_index + 1) begin
      system_sram_fabric_i.gen_bank[0].system_sram_i.sram_i.mem[128 + descriptor_index] =
          (descriptor_index == 256) ? 32'd0 :
          SYSTEM_SRAM_BASE_ADDR + 32'h1000 + 32'd32 * (descriptor_index + 1);
      system_sram_fabric_i.gen_bank[1].system_sram_i.sram_i.mem[128 + descriptor_index] =
          SYSTEM_SRAM_BASE_ADDR + 32'h4000;
      system_sram_fabric_i.gen_bank[2].system_sram_i.sram_i.mem[128 + descriptor_index] =
          SYSTEM_SRAM_BASE_ADDR + 32'h5000;
      system_sram_fabric_i.gen_bank[3].system_sram_i.sram_i.mem[128 + descriptor_index] = 32'd4;
      system_sram_fabric_i.gen_bank[4].system_sram_i.sram_i.mem[128 + descriptor_index] =
          (descriptor_index == 256) ? 32'h0000_001d : 32'h0000_0019;
      system_sram_fabric_i.gen_bank[5].system_sram_i.sram_i.mem[128 + descriptor_index] = 32'd0;
      system_sram_fabric_i.gen_bank[6].system_sram_i.sram_i.mem[128 + descriptor_index] = 32'd0;
    end
    system_sram_fabric_i.gen_bank[0].system_sram_i.sram_i.mem[512] = 32'h1234_5678;
    system_sram_fabric_i.gen_bank[0].system_sram_i.sram_i.mem[640] = 32'd0;
    cfg_write(6'h04, 32'h0000_000e);
    cfg_write(6'h14, SYSTEM_SRAM_BASE_ADDR + 32'h1000);
    cfg_write(6'h00, 32'h0000_000a);
    wait_idle_long();
    cfg_read(6'h04, status);
    check(status[2:0] == 3'b100, "overlong descriptor chain must set channel ERROR");
    check(system_sram_fabric_i.gen_bank[5].system_sram_i.sram_i.mem[128] == 32'h0000_0001 &&
          system_sram_fabric_i.gen_bank[5].system_sram_i.sram_i.mem[384] == 32'h0000_0002,
          "256th accepted and 257th rejected descriptor statuses");

    // Both response configurations must preserve the CPU load contract. Run
    // this after arbitration tests so it cannot change their round-robin seed.
    cpu_read(SYSTEM_SRAM_BASE_ADDR, 32'h1122_3344);

    if (errors == 0)
      $display("DMA SYSTEM SRAM PASS: copy and firewall denial");
    else
      $display("DMA SYSTEM SRAM FAIL: errors=%0d", errors);
    $finish;
  end
endmodule
