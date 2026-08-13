// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Converts abstract boot commands into the single instruction-memory write port.
// It owns the boot write address, optional auto-increment, and the fetch-release
// latch that keeps the CPU parked while a boot image is being loaded.
module imem_boot_ctrl #(
  parameter int IMEM_BOOT_ADDR_WIDTH = 13
) (
  // Clock and reset
  input  logic        clk,
  input  logic        rst_n,

  // Selected boot command
  input  logic        cmd_valid_i,
  input  logic        cmd_set_addr_i,
  input  logic        cmd_write_i,
  input  logic        cmd_hold_fetch_i,
  input  logic        cmd_release_fetch_i,
  input  logic        cmd_auto_inc_we_i,
  input  logic        cmd_auto_inc_i,
  input  logic [IMEM_BOOT_ADDR_WIDTH-1:0] cmd_addr_i,
  input  logic [31:0] cmd_wdata_i,
  input  logic [3:0]  cmd_be_i,

  // Boot-controller state view
  output logic [IMEM_BOOT_ADDR_WIDTH-1:0] current_addr_o,
  output logic        auto_inc_o,
  output logic        fetch_released_o,

  // IMEM boot-write port
  output logic        imem_boot_we_o,
  output logic [IMEM_BOOT_ADDR_WIDTH-1:0] imem_boot_addr_o,
  output logic [31:0] imem_boot_wdata_o,
  output logic [3:0]  imem_boot_be_o
);

  logic [IMEM_BOOT_ADDR_WIDTH-1:0] boot_addr_q;
  logic        auto_inc_q;
  logic        fetch_released_q;

  assign current_addr_o = boot_addr_q;
  assign auto_inc_o = auto_inc_q;
  assign fetch_released_o = fetch_released_q;


  // Commands are intentionally single-cycle pulses. Writes use the current boot
  // address, then optionally advance it for streaming loaders.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      boot_addr_q <= '0;
      auto_inc_q <= 1'b1;
      fetch_released_q <= 1'b0;
      imem_boot_we_o <= 1'b0;
      imem_boot_addr_o <= '0;
      imem_boot_wdata_o <= 32'h0000_0000;
      imem_boot_be_o <= 4'h0;
    end else begin
      imem_boot_we_o <= 1'b0;
      imem_boot_be_o <= 4'h0;

      if (cmd_valid_i) begin
        if (cmd_auto_inc_we_i) begin
          auto_inc_q <= cmd_auto_inc_i;
        end

        if (cmd_set_addr_i) begin
          boot_addr_q <= cmd_addr_i;
        end

        if (cmd_hold_fetch_i) begin
          fetch_released_q <= 1'b0;
        end

        if (cmd_release_fetch_i) begin
          fetch_released_q <= 1'b1;
        end

        if (cmd_write_i) begin
          imem_boot_we_o <= 1'b1;
          imem_boot_addr_o <= boot_addr_q;
          imem_boot_wdata_o <= cmd_wdata_i;
          imem_boot_be_o <= cmd_be_i;
          if (auto_inc_q) begin
            boot_addr_q <= boot_addr_q + 1;
          end
        end
      end
    end
  end

endmodule
