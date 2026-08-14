// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Core-level verification wrapper — NOT the delivery SoC.
// Wraps riscv_core with instr_mem, D-Cache, and clint_plic_mmio for standalone
// core verification. Use the delivery SoC for peripheral integration.
import riscv_pkg::*;

module riscv_wrapper #(
  parameter int IMEM_READ_LATENCY      = 1,
  parameter int DMEM_READ_LATENCY      = 1,
  parameter int IMEM_WORD_ADDR_WIDTH   = 13,
  parameter int DMEM_WORD_ADDR_WIDTH   = 13
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        fetch_enable_i,
  input  xlen_t       boot_addr_i,
  input  logic        debug_halt_req_i,
  input  logic        debug_resume_req_i,
  output logic        debug_halted_o,
  output logic        debug_running_o,
  output xlen_t       debug_pc_o,
  output logic [2:0]  debug_cause_o,
  input  logic [31:0] irq_i
);

  logic        imem_req;
  logic        imem_ready;
  paddr_t      imem_addr;
  logic        imem_rvalid;
  logic [31:0] imem_rdata;
  logic        data_req;
  paddr_t      data_addr;
  logic [63:0] data_wdata;
  logic        data_we;
  logic [7:0]  data_be;
  atomic_op_e  data_atomic_op;
  logic        data_atomic_aq, data_atomic_rl;
  logic        data_resp_valid;
  logic [63:0] data_rdata;
  logic        data_err;
  logic        data_fence;
  logic        cache_data_resp_valid;
  logic [63:0] cache_data_rdata;
  logic        cache_data_err;
  logic        cache_flush_done, cache_flush_err;
  logic        cache_line_req, cache_line_we, cache_line_resp_valid, cache_line_err;
  paddr_t      cache_line_addr;
  logic [511:0] cache_line_wdata, cache_line_rdata;
  logic [3:0]  cache_axi_awid, cache_axi_bid, cache_axi_arid, cache_axi_rid;
  paddr_t      cache_axi_awaddr, cache_axi_araddr;
  logic [7:0]  cache_axi_awlen, cache_axi_arlen;
  logic [2:0]  cache_axi_awsize, cache_axi_arsize;
  logic [1:0]  cache_axi_awburst, cache_axi_arburst;
  logic [3:0]  cache_axi_awcache, cache_axi_arcache;
  logic        cache_axi_awvalid, cache_axi_awready;
  logic        cache_axi_arvalid, cache_axi_arready;
  logic [63:0] cache_axi_wdata, cache_axi_rdata;
  logic [7:0]  cache_axi_wstrb;
  logic        cache_axi_wlast, cache_axi_wvalid, cache_axi_wready;
  logic [1:0]  cache_axi_bresp;
  logic        cache_axi_bvalid, cache_axi_bready;
  logic [1:0]  cache_axi_rresp;
  logic        cache_axi_rlast, cache_axi_rvalid, cache_axi_rready;
  logic        mmio_hit;
  logic        mmio_resp_valid;
  logic [63:0] mmio_rdata;
  logic        mmio_err;
  logic [63:0] mmio_mtime;
  logic [31:0] mmio_irq;
  logic [31:0] combined_irq;

  assign combined_irq = irq_i | mmio_irq;
  // The core-facing cache path is active for ordinary memory. MMIO bypasses
  // it, and atomics to MMIO fail instead of issuing an RMW sequence.
  assign data_resp_valid = mmio_hit ? mmio_resp_valid : cache_data_resp_valid;
  assign data_rdata      = mmio_hit ? mmio_rdata : cache_data_rdata;
  assign data_err        = mmio_hit ? (mmio_err | (data_atomic_op != ATOMIC_NONE)) : cache_data_err;

  riscv_core riscv_core_i (
    .clk              (clk),
    .rst_n            (rst_n),
    .fetch_enable_i   (fetch_enable_i),
    .boot_addr_i      (boot_addr_i),
    .debug_halt_req_i (debug_halt_req_i),
    .debug_resume_req_i(debug_resume_req_i),
    .debug_halted_o   (debug_halted_o),
    .debug_running_o  (debug_running_o),
    .debug_pc_o       (debug_pc_o),
    .debug_cause_o    (debug_cause_o),
    .debug_reg_req_valid_i(1'b0),
    .debug_reg_write_i     (1'b0),
    .debug_reg_addr_i      (16'h0),
    .debug_reg_wdata_i     ('0),
    .debug_reg_rdata_o     (),
    .debug_reg_error_o     (),
    .imem_req_o       (imem_req),
    .imem_ready_i     (imem_ready),
    .imem_addr_o      (imem_addr),
    .imem_rvalid_i    (imem_rvalid),
    .imem_rdata_i     (imem_rdata),
    .data_req_o       (data_req),
    .data_addr_o      (data_addr),
    .data_wdata_o     (data_wdata),
    .data_we_o        (data_we),
    .data_be_o        (data_be),
    .data_atomic_op_o (data_atomic_op),
    .data_atomic_aq_o (data_atomic_aq),
    .data_atomic_rl_o (data_atomic_rl),
    .data_resp_valid_i(data_resp_valid),
    .data_rdata_i     (data_rdata),
    .data_err_i       (data_err),
    .data_fence_o     (data_fence),
    .data_fence_done_i(cache_flush_done),
    .data_fence_err_i (cache_flush_err),
    // The standalone wrapper intentionally exercises the normal D-bus path.
    // Product SoC integration owns the optional DTCM early-load port.
    .lmem_req_o       (),
    .lmem_addr_o      (),
    .lmem_accept_i    (1'b0),
    .lmem_resp_valid_i(1'b0),
    .lmem_rdata_i     ('0),
    .lmem_err_i       (1'b0),
    .mtime_i          (mmio_mtime),
    .irq_i            (combined_irq),
    .wfi_wake_i       (1'b0),
    .wfi_sleep_o      ()
  );

  instr_mem #(
    .ADDR_WIDTH(IMEM_WORD_ADDR_WIDTH),
    .READ_LATENCY(IMEM_READ_LATENCY)
  ) instr_mem_i (
    .clk      (clk),
    .rst_n    (rst_n),
    .rd_req_i (imem_req),
    .ready_o  (imem_ready),
    // Memory ADDR_WIDTH is a word-index width; drop byte-lane bits [1:0].
    .addr_i   (imem_addr[IMEM_WORD_ADDR_WIDTH+1:2]),
    .rvalid_o (imem_rvalid),
    .instr_o  (imem_rdata),
    .boot_we_i         (1'b0),
    .boot_addr_i       ('0),
    .boot_wdata_i      ('0),
    .boot_be_i         (4'h0),
    .data_req_i       (1'b0),
    .data_we_i        (1'b0),
    .data_be_i        ('0),
    .data_addr_i      ('0),
    .data_wdata_i     ('0),
    .data_resp_valid_o(),
    .data_rdata_o     (),
    .data_err_o       ()
  );

  clint_plic_mmio #(
    .READ_LATENCY(DMEM_READ_LATENCY),
    .ADDR_WIDTH(PADDR_W),
    .DATA_WIDTH(64)
  ) clint_plic_mmio_i (
    .clk         (clk),
    .rst_n       (rst_n),
    .req_i       (data_req),
    .we_i        (data_we),
    .be_i        (data_be),
    .addr_i      (data_addr),
    .wdata_i     (data_wdata),
    .hit_o       (mmio_hit),
    .resp_valid_o(mmio_resp_valid),
    .rdata_o     (mmio_rdata),
    .err_o       (mmio_err),
    .mtime_o     (mmio_mtime),
    .irq_o       (mmio_irq)
  );

  dcache data_mem_i (
    .clk      (clk),
    .rst_n    (rst_n),
    .cpu_req_i(data_req && !mmio_hit),
    .cpu_addr_i(data_addr),
    .cpu_we_i     (data_we),
    .cpu_be_i     (data_be),
    .cpu_wdata_i  (data_wdata),
    .cpu_atomic_op_i(data_atomic_op),
    .cpu_resp_valid_o(cache_data_resp_valid),
    .cpu_rdata_o     (cache_data_rdata),
    .cpu_err_o       (cache_data_err),
    .flush_i         (data_fence),
    .flush_done_o    (cache_flush_done),
    .flush_err_o     (cache_flush_err),
    .line_req_o      (cache_line_req),
    .line_we_o       (cache_line_we),
    .line_addr_o     (cache_line_addr),
    .line_wdata_o    (cache_line_wdata),
    .line_resp_valid_i(cache_line_resp_valid),
    .line_rdata_i    (cache_line_rdata),
    .line_err_i      (cache_line_err)
  );

  cache_axi4_line_adapter data_cache_axi4_i (
    .clk(clk), .rst_n(rst_n),
    .line_req_i(cache_line_req), .line_we_i(cache_line_we),
    .line_addr_i(cache_line_addr), .line_wdata_i(cache_line_wdata),
    .line_resp_valid_o(cache_line_resp_valid), .line_rdata_o(cache_line_rdata),
    .line_err_o(cache_line_err),
    .m_axi_awid_o(cache_axi_awid), .m_axi_awaddr_o(cache_axi_awaddr),
    .m_axi_awlen_o(cache_axi_awlen), .m_axi_awsize_o(cache_axi_awsize),
    .m_axi_awburst_o(cache_axi_awburst), .m_axi_awcache_o(cache_axi_awcache),
    .m_axi_awvalid_o(cache_axi_awvalid), .m_axi_awready_i(cache_axi_awready),
    .m_axi_wdata_o(cache_axi_wdata), .m_axi_wstrb_o(cache_axi_wstrb),
    .m_axi_wlast_o(cache_axi_wlast), .m_axi_wvalid_o(cache_axi_wvalid),
    .m_axi_wready_i(cache_axi_wready),
    .m_axi_bid_i(cache_axi_bid), .m_axi_bresp_i(cache_axi_bresp),
    .m_axi_bvalid_i(cache_axi_bvalid), .m_axi_bready_o(cache_axi_bready),
    .m_axi_arid_o(cache_axi_arid), .m_axi_araddr_o(cache_axi_araddr),
    .m_axi_arlen_o(cache_axi_arlen), .m_axi_arsize_o(cache_axi_arsize),
    .m_axi_arburst_o(cache_axi_arburst), .m_axi_arcache_o(cache_axi_arcache),
    .m_axi_arvalid_o(cache_axi_arvalid), .m_axi_arready_i(cache_axi_arready),
    .m_axi_rid_i(cache_axi_rid), .m_axi_rdata_i(cache_axi_rdata),
    .m_axi_rresp_i(cache_axi_rresp), .m_axi_rlast_i(cache_axi_rlast),
    .m_axi_rvalid_i(cache_axi_rvalid), .m_axi_rready_o(cache_axi_rready)
  );

  axi4_line_mem #(
    .PADDR_W_P(PADDR_W),
    .AXI_DATA_W_P(64),
    .AXI_ID_W_P(4),
    .LINE_BYTES_P(64),
    .LINE_ADDR_W_P(DMEM_WORD_ADDR_WIDTH - 3)
  ) cache_backing_mem_i (
    .clk(clk), .rst_n(rst_n),
    .s_axi_awid_i(cache_axi_awid), .s_axi_awaddr_i(cache_axi_awaddr),
    .s_axi_awlen_i(cache_axi_awlen), .s_axi_awsize_i(cache_axi_awsize),
    .s_axi_awburst_i(cache_axi_awburst), .s_axi_awcache_i(cache_axi_awcache),
    .s_axi_awvalid_i(cache_axi_awvalid), .s_axi_awready_o(cache_axi_awready),
    .s_axi_wdata_i(cache_axi_wdata), .s_axi_wstrb_i(cache_axi_wstrb),
    .s_axi_wlast_i(cache_axi_wlast), .s_axi_wvalid_i(cache_axi_wvalid),
    .s_axi_wready_o(cache_axi_wready),
    .s_axi_bid_o(cache_axi_bid), .s_axi_bresp_o(cache_axi_bresp),
    .s_axi_bvalid_o(cache_axi_bvalid), .s_axi_bready_i(cache_axi_bready),
    .s_axi_arid_i(cache_axi_arid), .s_axi_araddr_i(cache_axi_araddr),
    .s_axi_arlen_i(cache_axi_arlen), .s_axi_arsize_i(cache_axi_arsize),
    .s_axi_arburst_i(cache_axi_arburst), .s_axi_arcache_i(cache_axi_arcache),
    .s_axi_arvalid_i(cache_axi_arvalid), .s_axi_arready_o(cache_axi_arready),
    .s_axi_rid_o(cache_axi_rid), .s_axi_rdata_o(cache_axi_rdata),
    .s_axi_rresp_o(cache_axi_rresp), .s_axi_rlast_o(cache_axi_rlast),
    .s_axi_rvalid_o(cache_axi_rvalid), .s_axi_rready_i(cache_axi_rready)
  );

endmodule
