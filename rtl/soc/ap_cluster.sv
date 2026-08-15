// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Cluster boundary. It owns the common Boot ROM. The current contract
// contains exactly one hart tile; multi-hart replication is deferred until
// ap_memory_system provides a coherent L2/directory path.
import ap_soc_pkg::*;

module ap_cluster #(
  parameter int unsigned BOOT_ROM_SIZE_BYTES_P = 64 * 1024,
  parameter string BOOT_ROM_INIT_FILE_P = "",
  parameter bit ENABLE_BHT_P = 1'b1,
  parameter bit ENABLE_RAS_P = 1'b1,
  parameter bit ENABLE_UPPER_32_PREFETCH_P = 1'b1,
  parameter int unsigned MUL_ITER_BITS_P = 16
) (
  input logic clk,
  input logic rst_n,
  input logic fetch_enable_i,
  input logic [63:0] mtime_i,
  input logic [31:0] irq_i,
  input logic debug_halt_req_i,
  input logic debug_resume_req_i,
  output logic debug_halted_o,
  output logic debug_running_o,
  output logic [63:0] debug_pc_o,
  output logic [2:0] debug_cause_o,
  AXI_BUS.Master mem_axi_o [1:0],
  AXI_BUS.Master periph_axi_o
);

  logic boot_imem_req;
  logic [AP_PADDR_W-1:0] boot_imem_addr;
  logic boot_imem_ready;
  logic boot_imem_rvalid;
  logic [31:0] boot_imem_rdata;

  ap_hart_tile #(
    .BOOT_ROM_SIZE_BYTES_P(BOOT_ROM_SIZE_BYTES_P),
    .ENABLE_BHT_P(ENABLE_BHT_P),
    .ENABLE_RAS_P(ENABLE_RAS_P),
    .ENABLE_UPPER_32_PREFETCH_P(ENABLE_UPPER_32_PREFETCH_P),
    .MUL_ITER_BITS_P(MUL_ITER_BITS_P)
  ) hart_tile_i (
    .clk(clk),
    .rst_n(rst_n),
    .fetch_enable_i(fetch_enable_i),
    .mtime_i(mtime_i),
    .irq_i(irq_i),
    .debug_halt_req_i(debug_halt_req_i),
    .debug_resume_req_i(debug_resume_req_i),
    .debug_halted_o(debug_halted_o),
    .debug_running_o(debug_running_o),
    .debug_pc_o(debug_pc_o),
    .debug_cause_o(debug_cause_o),
    .boot_imem_req_o(boot_imem_req),
    .boot_imem_addr_o(boot_imem_addr),
    .boot_imem_ready_i(boot_imem_ready),
    .boot_imem_rvalid_i(boot_imem_rvalid),
    .boot_imem_rdata_i(boot_imem_rdata),
    .mem_axi_o(mem_axi_o),
    .periph_axi_o(periph_axi_o)
  );

  ap_boot_rom #(
    .SIZE_BYTES_P(BOOT_ROM_SIZE_BYTES_P),
    .INIT_FILE_P(BOOT_ROM_INIT_FILE_P)
  ) boot_rom_i (
    .clk(clk),
    .rst_n(rst_n),
    .req_i(boot_imem_req),
    .addr_i(boot_imem_addr),
    .ready_o(boot_imem_ready),
    .rvalid_o(boot_imem_rvalid),
    .rdata_o(boot_imem_rdata)
  );

endmodule
