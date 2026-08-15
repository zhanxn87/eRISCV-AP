// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Single AP hart tile structural boundary. Behavioral memory, MMU, cache, and
// routing logic belongs to ap_hart_memory_frontend; this module only wires the
// RV64GC core to that frontend and exports its three AXI managers.
import ap_soc_pkg::*;
import riscv_pkg::*;

module ap_hart_tile #(
  parameter int unsigned BOOT_ROM_SIZE_BYTES_P = 64 * 1024,
  parameter bit ENABLE_BHT_P = 1'b1,
  parameter bit ENABLE_RAS_P = 1'b1,
  parameter bit ENABLE_UPPER_32_PREFETCH_P = 1'b1,
  parameter int unsigned MUL_ITER_BITS_P = 16
) (
  // Clock and reset.
  input logic clk,
  input logic rst_n,

  // Hart run control and asynchronous architectural events.
  input logic fetch_enable_i,
  input logic [63:0] mtime_i,
  input logic [31:0] irq_i,

  // External debug run control and halt-state observation.
  input logic debug_halt_req_i,
  input logic debug_resume_req_i,
  output logic debug_halted_o,
  output logic debug_running_o,
  output xlen_t debug_pc_o,
  output logic [2:0] debug_cause_o,

  // Cluster-owned shared Boot ROM fetch port.
  output logic boot_imem_req_o,
  output logic [AP_PADDR_W-1:0] boot_imem_addr_o,
  input logic boot_imem_ready_i,
  input logic boot_imem_rvalid_i,
  input logic [31:0] boot_imem_rdata_i,

  // Cached DDR managers on axi_mem: [0] I-Cache, [1] D-Cache.
  AXI_BUS.Master mem_axi_o [1:0],

  // Uncached translated physical MMIO manager on axi_periph.
  AXI_BUS.Master periph_axi_o
);

  // Core-to-memory-frontend virtual interfaces.
  logic imem_req;
  logic imem_ready;
  logic imem_rvalid;
  logic imem_page_fault;
  logic imem_access_fault;
  xlen_t imem_addr;
  logic [31:0] imem_rdata;

  logic data_req;
  logic data_req_ready;
  logic data_we;
  logic data_resp_valid;
  logic data_err;
  logic data_page_fault;
  xlen_t data_addr;
  logic [63:0] data_wdata;
  logic [63:0] data_rdata;
  logic [7:0] data_be;
  logic [3:0] data_atomic_op;
  logic data_fence;
  logic data_fence_done;
  logic data_fence_err;

  // Core CSR context consumed by the Sv39 frontend.
  xlen_t hart_satp;
  privilege_mode_e hart_privilege;
  privilege_mode_e hart_mstatus_mpp;
  logic hart_mstatus_sum;
  logic hart_mstatus_mxr;
  logic hart_mstatus_mprv;
  logic hart_sfence_vma;
  xlen_t hart_sfence_vma_vaddr;
  logic [15:0] hart_sfence_vma_asid;

  riscv_core #(
    .RESET_VECTOR_ADDR_P(AP_BOOT_ROM_BASE + 48'h80),
    .DEBUG_BASE_ADDR_P(AP_BOOT_ROM_BASE + 48'h100),
    .ENABLE_LOAD_RESPONSE_BYPASS_P(1'b1),
    .ENABLE_BHT_P(ENABLE_BHT_P),
    .ENABLE_RAS_P(ENABLE_RAS_P),
    .ENABLE_UPPER_32_PREFETCH_P(ENABLE_UPPER_32_PREFETCH_P),
    .MUL_ITER_BITS_P(MUL_ITER_BITS_P)
  ) riscv_core_i (
    .clk(clk),
    .rst_n(rst_n),
    .fetch_enable_i(fetch_enable_i),
    .boot_addr_i(AP_BOOT_ROM_BASE + 48'h80),
    .debug_halt_req_i(debug_halt_req_i),
    .debug_resume_req_i(debug_resume_req_i),
    .debug_halted_o(debug_halted_o),
    .debug_running_o(debug_running_o),
    .debug_pc_o(debug_pc_o),
    .debug_cause_o(debug_cause_o),
    .debug_reg_req_valid_i(1'b0),
    .debug_reg_write_i(1'b0),
    .debug_reg_addr_i('0),
    .debug_reg_wdata_i('0),
    .debug_reg_rdata_o(),
    .debug_reg_error_o(),
    .imem_req_o(imem_req),
    .imem_ready_i(imem_ready),
    .imem_addr_o(imem_addr),
    .imem_rvalid_i(imem_rvalid),
    .imem_rdata_i(imem_rdata),
    .imem_page_fault_i(imem_page_fault),
    .imem_access_fault_i(imem_access_fault),
    .data_req_o(data_req),
    .data_req_ready_i(data_req_ready),
    .data_addr_o(data_addr),
    .data_wdata_o(data_wdata),
    .data_we_o(data_we),
    .data_be_o(data_be),
    .data_atomic_op_o(data_atomic_op),
    .data_atomic_aq_o(),
    .data_atomic_rl_o(),
    .data_resp_valid_i(data_resp_valid),
    .data_rdata_i(data_rdata),
    .data_err_i(data_err),
    .data_page_fault_i(data_page_fault),
    .data_fence_o(data_fence),
    .data_fence_done_i(data_fence_done),
    .data_fence_err_i(data_fence_err),
    .mtime_i(mtime_i),
    .irq_i(irq_i),
    .wfi_wake_i(|irq_i),
    .wfi_sleep_o(),
    .satp_o(hart_satp),
    .privilege_mode_o(hart_privilege),
    .mstatus_sum_o(hart_mstatus_sum),
    .mstatus_mxr_o(hart_mstatus_mxr),
    .mstatus_mprv_o(hart_mstatus_mprv),
    .mstatus_mpp_o(hart_mstatus_mpp),
    .sfence_vma_o(hart_sfence_vma),
    .sfence_vma_vaddr_o(hart_sfence_vma_vaddr),
    .sfence_vma_asid_o(hart_sfence_vma_asid)
  );

  ap_hart_memory_frontend #(
    .BOOT_ROM_SIZE_BYTES_P(BOOT_ROM_SIZE_BYTES_P)
  ) memory_frontend_i (
    .clk(clk),
    .rst_n(rst_n),
    .imem_req(imem_req),
    .imem_ready(imem_ready),
    .imem_addr(imem_addr),
    .imem_rvalid(imem_rvalid),
    .imem_rdata(imem_rdata),
    .imem_page_fault(imem_page_fault),
    .imem_access_fault(imem_access_fault),
    .data_req(data_req),
    .data_req_ready(data_req_ready),
    .data_addr(data_addr),
    .data_wdata(data_wdata),
    .data_we(data_we),
    .data_be(data_be),
    .data_atomic_op(data_atomic_op),
    .data_resp_valid(data_resp_valid),
    .data_rdata(data_rdata),
    .data_err(data_err),
    .data_page_fault(data_page_fault),
    .data_fence(data_fence),
    .data_fence_done(data_fence_done),
    .data_fence_err(data_fence_err),
    .hart_satp(hart_satp),
    .hart_privilege(hart_privilege),
    .hart_mstatus_mpp(hart_mstatus_mpp),
    .hart_mstatus_sum(hart_mstatus_sum),
    .hart_mstatus_mxr(hart_mstatus_mxr),
    .hart_mstatus_mprv(hart_mstatus_mprv),
    .hart_sfence_vma(hart_sfence_vma),
    .hart_sfence_vma_vaddr(hart_sfence_vma_vaddr),
    .hart_sfence_vma_asid(hart_sfence_vma_asid),
    .boot_imem_req_o(boot_imem_req_o),
    .boot_imem_addr_o(boot_imem_addr_o),
    .boot_imem_ready_i(boot_imem_ready_i),
    .boot_imem_rvalid_i(boot_imem_rvalid_i),
    .boot_imem_rdata_i(boot_imem_rdata_i),
    .mem_axi_o(mem_axi_o),
    .periph_axi_o(periph_axi_o)
  );

endmodule
