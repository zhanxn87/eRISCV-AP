// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Cluster boundary. The current contract contains exactly one hart tile;
// multi-hart replication is deferred until ap_memory_system provides a
// coherent L2/directory path.
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
  AXI_BUS.Master mem_axi_o [1:0],
  AXI_BUS.Master periph_axi_o
);

  ap_hart_tile #(
    .BOOT_ROM_SIZE_BYTES_P(BOOT_ROM_SIZE_BYTES_P),
    .BOOT_ROM_INIT_FILE_P(BOOT_ROM_INIT_FILE_P),
    .ENABLE_BHT_P(ENABLE_BHT_P),
    .ENABLE_RAS_P(ENABLE_RAS_P),
    .ENABLE_UPPER_32_PREFETCH_P(ENABLE_UPPER_32_PREFETCH_P),
    .MUL_ITER_BITS_P(MUL_ITER_BITS_P)
  ) hart_tile_i (
    .clk,
    .rst_n,
    .fetch_enable_i,
    .mtime_i,
    .irq_i,
    .mem_axi_o,
    .periph_axi_o
  );

endmodule
