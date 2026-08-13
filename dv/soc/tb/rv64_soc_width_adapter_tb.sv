// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// Focused RV64 SoC boundary test: 48-bit physical addresses, 64-bit core
// accesses, and the retained 32-bit TCM/peripheral fabric.
module rv64_soc_width_adapter_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic        dbus_req, dbus_we, dbus_resp_valid, dbus_err;
  logic [47:0] dbus_addr;
  logic [63:0] dbus_wdata, dbus_rdata;
  logic [7:0]  dbus_be;
  logic        legacy_req, legacy_we, legacy_resp_valid, legacy_err;
  logic [31:0] legacy_addr, legacy_wdata, legacy_rdata;
  logic [3:0]  legacy_be;
  logic [31:0] dbus_mem [0:7];

  logic        lmem_req, lmem_accept, lmem_resp_valid, lmem_err;
  logic [47:0] lmem_addr;
  logic [63:0] lmem_rdata;
  logic        lmem_legacy_req, lmem_legacy_accept, lmem_legacy_resp_valid, lmem_legacy_err;
  logic [31:0] lmem_legacy_addr, lmem_legacy_rdata;
  logic [31:0] lmem_mem [0:3];

  logic        imem_req, imem_ready, imem_rvalid;
  logic [47:0] imem_addr;
  logic [31:0] imem_rdata;
  logic        imem_legacy_req, imem_legacy_ready, imem_legacy_rvalid;
  logic [31:0] imem_legacy_addr, imem_legacy_rdata;

  dbus64_to_dbus32_adapter dbus_dut (
    .clk, .rst_n,
    .dbus_req_i(dbus_req), .dbus_addr_i(dbus_addr), .dbus_wdata_i(dbus_wdata),
    .dbus_we_i(dbus_we), .dbus_be_i(dbus_be), .dbus_resp_valid_o(dbus_resp_valid),
    .dbus_rdata_o(dbus_rdata), .dbus_err_o(dbus_err),
    .legacy_req_o(legacy_req), .legacy_addr_o(legacy_addr), .legacy_wdata_o(legacy_wdata),
    .legacy_we_o(legacy_we), .legacy_be_o(legacy_be), .legacy_resp_valid_i(legacy_resp_valid),
    .legacy_rdata_i(legacy_rdata), .legacy_err_i(legacy_err)
  );

  lmem64_to_lmem32_adapter lmem_dut (
    .clk, .rst_n,
    .lmem_req_i(lmem_req), .lmem_addr_i(lmem_addr), .lmem_accept_o(lmem_accept),
    .lmem_resp_valid_o(lmem_resp_valid), .lmem_rdata_o(lmem_rdata), .lmem_err_o(lmem_err),
    .legacy_req_o(lmem_legacy_req), .legacy_addr_o(lmem_legacy_addr),
    .legacy_accept_i(lmem_legacy_accept), .legacy_resp_valid_i(lmem_legacy_resp_valid),
    .legacy_rdata_i(lmem_legacy_rdata), .legacy_err_i(lmem_legacy_err)
  );

  ibus48_to_ibus32_adapter ibus_dut (
    .clk, .rst_n,
    .imem_req_i(imem_req), .imem_addr_i(imem_addr), .imem_ready_o(imem_ready),
    .imem_rvalid_o(imem_rvalid), .imem_rdata_o(imem_rdata),
    .legacy_req_o(imem_legacy_req), .legacy_addr_o(imem_legacy_addr),
    .legacy_ready_i(imem_legacy_ready), .legacy_rvalid_i(imem_legacy_rvalid),
    .legacy_rdata_i(imem_legacy_rdata)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      legacy_resp_valid <= 1'b0;
      legacy_rdata <= '0;
      legacy_err <= 1'b0;
    end else begin
      legacy_resp_valid <= legacy_req;
      legacy_rdata <= dbus_mem[legacy_addr[4:2]];
      legacy_err <= 1'b0;
      if (legacy_req && legacy_we) begin
        for (int byte_index = 0; byte_index < 4; byte_index++) begin
          if (legacy_be[byte_index])
            dbus_mem[legacy_addr[4:2]][byte_index*8 +: 8] <= legacy_wdata[byte_index*8 +: 8];
        end
      end
    end
  end

  assign lmem_legacy_accept = 1'b1;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lmem_legacy_resp_valid <= 1'b0;
      lmem_legacy_rdata <= '0;
      lmem_legacy_err <= 1'b0;
    end else begin
      lmem_legacy_resp_valid <= lmem_legacy_req;
      lmem_legacy_rdata <= lmem_mem[lmem_legacy_addr[3:2]];
      lmem_legacy_err <= 1'b0;
    end
  end

  assign imem_legacy_ready = 1'b1;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      imem_legacy_rvalid <= 1'b0;
      imem_legacy_rdata <= '0;
    end else begin
      imem_legacy_rvalid <= imem_legacy_req;
      imem_legacy_rdata <= 32'h0000_0013;
    end
  end

  task automatic dbus_access(
    input logic [47:0] addr,
    input logic [63:0] wdata,
    input logic        we,
    input logic [7:0]  be,
    input logic [63:0] expected_rdata,
    input logic        expected_err
  );
    begin
      @(negedge clk);
      dbus_addr = addr;
      dbus_wdata = wdata;
      dbus_we = we;
      dbus_be = be;
      dbus_req = 1'b1;
      @(negedge clk);
      dbus_req = 1'b0;
      do @(posedge clk); while (!dbus_resp_valid);
      if (((!we) && (dbus_rdata !== expected_rdata)) || (dbus_err !== expected_err))
        $fatal(1, "DBUS addr=%h got rdata=%h err=%b expected rdata=%h err=%b",
               addr, dbus_rdata, dbus_err, expected_rdata, expected_err);
    end
  endtask

  initial begin
    dbus_req = 1'b0;
    dbus_addr = '0;
    dbus_wdata = '0;
    dbus_we = 1'b0;
    dbus_be = '0;
    lmem_req = 1'b0;
    lmem_addr = '0;
    imem_req = 1'b0;
    imem_addr = '0;
    dbus_mem[0] = 32'h1122_3344;
    dbus_mem[1] = 32'h5566_7788;
    lmem_mem[0] = 32'h89ab_cdef;
    lmem_mem[1] = 32'h0123_4567;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    // LD uses two legacy words; a 32-bit load on the upper word uses one.
    dbus_access(48'h0000_1100_0000, '0, 1'b0, 8'hff, 64'h5566_7788_1122_3344, 1'b0);
    dbus_access(48'h0000_1100_0004, '0, 1'b0, 8'hf0, 64'h5566_7788_0000_0000, 1'b0);
    dbus_access(48'h0000_1100_0000, 64'h0123_4567_89ab_cdef, 1'b1, 8'hff, '0, 1'b0);
    if ((dbus_mem[0] !== 32'h89ab_cdef) || (dbus_mem[1] !== 32'h0123_4567))
      $fatal(1, "SD did not split into two little-endian words");
    dbus_access(48'h0000_1100_0005, 64'h0000_aa00_0000_0000, 1'b1, 8'h20, '0, 1'b0);
    if (dbus_mem[1] !== 32'h0123_aa67)
      $fatal(1, "SB lane adaptation failed: %h", dbus_mem[1]);
    dbus_access(48'h0001_0000_0000, '0, 1'b0, 8'h0f, '0, 1'b1);

    // The early DTCM read returns the complete aligned RV64 word.
    @(negedge clk);
    lmem_addr = 48'h0000_1100_0000;
    lmem_req = 1'b1;
    @(posedge clk);
    if (!lmem_accept)
      $fatal(1, "DTCM early-load request was not accepted");
    @(negedge clk);
    lmem_req = 1'b0;
    do @(posedge clk); while (!lmem_resp_valid);
    if ((lmem_rdata !== 64'h0123_4567_89ab_cdef) || lmem_err)
      $fatal(1, "DTCM early-load assembly failed: rdata=%h err=%b", lmem_rdata, lmem_err);

    // A fetch above the legacy aperture must not alias into low ITCM.
    @(negedge clk);
    imem_addr = 48'h0001_1000_0000;
    imem_req = 1'b1;
    @(posedge clk);
    if (!imem_ready || imem_legacy_req)
      $fatal(1, "High physical fetch was not rejected at the boundary");
    @(negedge clk);
    imem_req = 1'b0;
    do @(posedge clk); while (!imem_rvalid);
    if (imem_rdata !== 32'h0000_0000)
      $fatal(1, "High physical fetch did not return an illegal instruction");

    $display("RV64_SOC_WIDTH_ADAPTER PASS");
    $finish;
  end
endmodule
