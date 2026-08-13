// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Fixed-priority boot command arbiter.
// Only one source is expected to be enabled by boot_mode_i, but priority keeps
// behavior deterministic if sources accidentally pulse in the same cycle.
module boot_source_arbiter #(
  parameter int BOOT_ADDR_WIDTH = 13
) (
  // DMI boot-command source (src0, highest priority)
  input  logic        src0_valid_i,
  input  logic        src0_set_addr_i,
  input  logic        src0_write_i,
  input  logic        src0_hold_fetch_i,
  input  logic        src0_release_fetch_i,
  input  logic        src0_auto_inc_we_i,
  input  logic        src0_auto_inc_i,
  input  logic [BOOT_ADDR_WIDTH-1:0] src0_addr_i,
  input  logic [31:0] src0_wdata_i,
  input  logic [3:0]  src0_be_i,

  // UART boot-command source (src1)
  input  logic        src1_valid_i,
  input  logic        src1_set_addr_i,
  input  logic        src1_write_i,
  input  logic        src1_hold_fetch_i,
  input  logic        src1_release_fetch_i,
  input  logic        src1_auto_inc_we_i,
  input  logic        src1_auto_inc_i,
  input  logic [BOOT_ADDR_WIDTH-1:0] src1_addr_i,
  input  logic [31:0] src1_wdata_i,
  input  logic [3:0]  src1_be_i,

  // Reserved boot-command source (src2)
  input  logic        src2_valid_i,
  input  logic        src2_set_addr_i,
  input  logic        src2_write_i,
  input  logic        src2_hold_fetch_i,
  input  logic        src2_release_fetch_i,
  input  logic        src2_auto_inc_we_i,
  input  logic        src2_auto_inc_i,
  input  logic [BOOT_ADDR_WIDTH-1:0] src2_addr_i,
  input  logic [31:0] src2_wdata_i,
  input  logic [3:0]  src2_be_i,

  // Selected command to the IMEM boot controller
  output logic        cmd_valid_o,
  output logic        cmd_set_addr_o,
  output logic        cmd_write_o,
  output logic        cmd_hold_fetch_o,
  output logic        cmd_release_fetch_o,
  output logic        cmd_auto_inc_we_o,
  output logic        cmd_auto_inc_o,
  output logic [BOOT_ADDR_WIDTH-1:0] cmd_addr_o,
  output logic [31:0] cmd_wdata_o,
  output logic [3:0]  cmd_be_o
);


  // src0 has highest priority, then src1, then src2. The command payload is
  // copied combinationally so imem_boot_ctrl sees a single-cycle command pulse.
  always_comb begin
    cmd_valid_o = 1'b0;
    cmd_set_addr_o = 1'b0;
    cmd_write_o = 1'b0;
    cmd_hold_fetch_o = 1'b0;
    cmd_release_fetch_o = 1'b0;
    cmd_auto_inc_we_o = 1'b0;
    cmd_auto_inc_o = 1'b0;
    cmd_addr_o = '0;
    cmd_wdata_o = 32'h0000_0000;
    cmd_be_o = 4'h0;

    if (src0_valid_i) begin
      cmd_valid_o = src0_valid_i;
      cmd_set_addr_o = src0_set_addr_i;
      cmd_write_o = src0_write_i;
      cmd_hold_fetch_o = src0_hold_fetch_i;
      cmd_release_fetch_o = src0_release_fetch_i;
      cmd_auto_inc_we_o = src0_auto_inc_we_i;
      cmd_auto_inc_o = src0_auto_inc_i;
      cmd_addr_o = src0_addr_i;
      cmd_wdata_o = src0_wdata_i;
      cmd_be_o = src0_be_i;
    end else if (src1_valid_i) begin
      cmd_valid_o = src1_valid_i;
      cmd_set_addr_o = src1_set_addr_i;
      cmd_write_o = src1_write_i;
      cmd_hold_fetch_o = src1_hold_fetch_i;
      cmd_release_fetch_o = src1_release_fetch_i;
      cmd_auto_inc_we_o = src1_auto_inc_we_i;
      cmd_auto_inc_o = src1_auto_inc_i;
      cmd_addr_o = src1_addr_i;
      cmd_wdata_o = src1_wdata_i;
      cmd_be_o = src1_be_i;
    end else if (src2_valid_i) begin
      cmd_valid_o = src2_valid_i;
      cmd_set_addr_o = src2_set_addr_i;
      cmd_write_o = src2_write_i;
      cmd_hold_fetch_o = src2_hold_fetch_i;
      cmd_release_fetch_o = src2_release_fetch_i;
      cmd_auto_inc_we_o = src2_auto_inc_we_i;
      cmd_auto_inc_o = src2_auto_inc_i;
      cmd_addr_o = src2_addr_i;
      cmd_wdata_o = src2_wdata_i;
      cmd_be_o = src2_be_i;
    end
  end

endmodule
