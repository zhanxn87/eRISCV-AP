// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Single AP hart tile. It owns the RV64GC hart, Boot ROM fetch path, private
// physical L1 caches, and the early split between cacheable DDR and uncached
// device traffic. Sv39 will insert ITLB/DTLB/PTW at the existing core-facing
// fetch/data boundaries without changing these physical AXI master ports.
import ap_soc_pkg::*;

module ap_hart_tile #(
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

  // axi_mem managers: [0] I-Cache, [1] D-Cache.
  AXI_BUS.Master mem_axi_o [1:0],
  // axi_periph manager: translated physical MMIO only.
  AXI_BUS.Master periph_axi_o
);

  // -------------------------------------------------------------------------
  // Hart fetch, data, and maintenance interfaces
  // -------------------------------------------------------------------------
  logic imem_req, imem_ready, imem_rvalid;
  logic [AP_PADDR_W-1:0] imem_addr;
  logic [31:0] imem_rdata;
  logic boot_imem_req, boot_imem_ready, boot_imem_rvalid;
  logic [31:0] boot_imem_rdata;
  logic icache_imem_req, icache_imem_ready, icache_imem_rvalid;
  logic [31:0] icache_imem_rdata;
  logic icache_invalidate_done;
  logic unmapped_imem_req, unmapped_imem_rvalid_q;

  logic data_req, data_we, data_resp_valid, data_err;
  logic [AP_PADDR_W-1:0] data_addr;
  logic [63:0] data_wdata, data_rdata;
  logic [7:0] data_be;
  logic [3:0] data_atomic_op;
  logic data_atomic_aq, data_atomic_rl;
  logic data_fence, data_fence_done, data_fence_err;

  // -------------------------------------------------------------------------
  // D-Cache and uncached CPU device path
  // -------------------------------------------------------------------------
  logic dcache_cpu_req, dcache_cpu_we, dcache_cpu_resp_valid, dcache_cpu_err;
  logic [AP_PADDR_W-1:0] dcache_cpu_addr;
  logic [63:0] dcache_cpu_wdata, dcache_cpu_rdata;
  logic [7:0] dcache_cpu_be;
  logic [3:0] dcache_cpu_atomic_op;
  logic dcache_flush_done, dcache_flush_err;
  logic dcache_line_req, dcache_line_we, dcache_line_resp_valid, dcache_line_err;
  logic [AP_PADDR_W-1:0] dcache_line_addr;
  logic [511:0] dcache_line_wdata, dcache_line_rdata;

  logic uncached_cpu_req, uncached_cpu_we;
  logic [AP_PADDR_W-1:0] uncached_cpu_addr;
  logic [63:0] uncached_cpu_wdata, uncached_cpu_rdata;
  logic [7:0] uncached_cpu_be;
  logic uncached_cpu_resp_valid, uncached_cpu_err;

  // -------------------------------------------------------------------------
  // Flattened AXI links. I-Cache and D-Cache own distinct axi_mem managers;
  // the uncached device master owns the independent axi_periph manager. The
  // interface bridges only adapt sidebands and do not arbitrate those planes.
  // -------------------------------------------------------------------------
  logic icache_line_req, icache_line_resp_valid, icache_line_err;
  logic [AP_PADDR_W-1:0] icache_line_addr;
  logic [511:0] icache_line_rdata;
  logic [AP_AXI_SLV_ID_W-1:0] icache_awid, icache_bid, icache_arid, icache_rid;
  logic [AP_PADDR_W-1:0] icache_awaddr, icache_araddr;
  logic [7:0] icache_awlen, icache_arlen;
  logic [2:0] icache_awsize, icache_arsize;
  logic [1:0] icache_awburst, icache_arburst, icache_bresp, icache_rresp;
  logic [3:0] icache_awcache, icache_arcache;
  logic icache_awvalid, icache_awready, icache_wlast, icache_wvalid, icache_wready;
  logic icache_bvalid, icache_bready, icache_arvalid, icache_arready;
  logic icache_rlast, icache_rvalid, icache_rready;
  logic [63:0] icache_wdata, icache_rdata;
  logic [7:0] icache_wstrb;

  logic [AP_AXI_SLV_ID_W-1:0] dcache_awid, dcache_bid, dcache_arid, dcache_rid;
  logic [AP_PADDR_W-1:0] dcache_awaddr, dcache_araddr;
  logic [7:0] dcache_awlen, dcache_arlen;
  logic [2:0] dcache_awsize, dcache_arsize;
  logic [1:0] dcache_awburst, dcache_arburst, dcache_bresp, dcache_rresp;
  logic [3:0] dcache_awcache, dcache_arcache;
  logic dcache_awvalid, dcache_awready, dcache_wlast, dcache_wvalid, dcache_wready;
  logic dcache_bvalid, dcache_bready, dcache_arvalid, dcache_arready;
  logic dcache_rlast, dcache_rvalid, dcache_rready;
  logic [63:0] dcache_wdata, dcache_rdata;
  logic [7:0] dcache_wstrb;

  logic [AP_AXI_SLV_ID_W-1:0] uncached_awid, uncached_bid, uncached_arid, uncached_rid;
  logic [AP_PADDR_W-1:0] uncached_awaddr, uncached_araddr;
  logic [7:0] uncached_awlen, uncached_arlen;
  logic [2:0] uncached_awsize, uncached_arsize;
  logic [1:0] uncached_awburst, uncached_arburst, uncached_bresp, uncached_rresp;
  logic [3:0] uncached_awcache, uncached_arcache;
  logic uncached_awvalid, uncached_awready, uncached_wlast, uncached_wvalid, uncached_wready;
  logic uncached_bvalid, uncached_bready, uncached_arvalid, uncached_arready;
  logic uncached_rlast, uncached_rvalid, uncached_rready;
  logic [63:0] uncached_wdata, uncached_rdata;
  logic [7:0] uncached_wstrb;

  // -------------------------------------------------------------------------
  // Boot ROM and RV64GC hart
  // -------------------------------------------------------------------------
  ap_boot_rom #(
    .SIZE_BYTES_P(BOOT_ROM_SIZE_BYTES_P),
    .INIT_FILE_P(BOOT_ROM_INIT_FILE_P)
  ) boot_rom_i (
    .clk(clk), .rst_n(rst_n),
    .req_i(boot_imem_req), .addr_i(imem_addr),
    .ready_o(boot_imem_ready), .rvalid_o(boot_imem_rvalid), .rdata_o(boot_imem_rdata)
  );

  icache icache_i (
    .clk(clk), .rst_n(rst_n), .cpu_req_i(icache_imem_req), .cpu_addr_i(imem_addr),
    .invalidate_i(data_fence), .invalidate_done_o(icache_invalidate_done),
    .cpu_ready_o(icache_imem_ready), .cpu_rvalid_o(icache_imem_rvalid),
    .cpu_rdata_o(icache_imem_rdata), .line_req_o(icache_line_req),
    .line_addr_o(icache_line_addr), .line_resp_valid_i(icache_line_resp_valid),
    .line_rdata_i(icache_line_rdata), .line_err_i(icache_line_err)
  );

  assign boot_imem_req = imem_req && ap_addr_in_range(imem_addr, AP_BOOT_ROM_BASE,
                                                       AP_BOOT_ROM_BASE + BOOT_ROM_SIZE_BYTES_P);
  assign icache_imem_req = imem_req && ap_is_ddr_addr(imem_addr);
  assign unmapped_imem_req = imem_req && !boot_imem_req && !icache_imem_req;
  assign imem_ready = boot_imem_req ? boot_imem_ready :
                      icache_imem_req ? icache_imem_ready : 1'b1;
  assign imem_rvalid = boot_imem_rvalid || icache_imem_rvalid || unmapped_imem_rvalid_q;
  assign imem_rdata = boot_imem_rvalid ? boot_imem_rdata :
                      icache_imem_rvalid ? icache_imem_rdata : 32'h0000_0013;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      unmapped_imem_rvalid_q <= 1'b0;
    else
      unmapped_imem_rvalid_q <= unmapped_imem_req;
  end

  riscv_core #(
    .RESET_VECTOR_ADDR_P(AP_BOOT_ROM_BASE + 48'h80),
    .DEBUG_BASE_ADDR_P(AP_BOOT_ROM_BASE + 48'h100),
    .ENABLE_LMEM_EARLY_LOAD_P(1'b0),
    .ENABLE_LOAD_RESPONSE_BYPASS_P(1'b1),
    .ENABLE_BHT_P(ENABLE_BHT_P),
    .ENABLE_RAS_P(ENABLE_RAS_P),
    .ENABLE_UPPER_32_PREFETCH_P(ENABLE_UPPER_32_PREFETCH_P),
    .MUL_ITER_BITS_P(MUL_ITER_BITS_P)
  ) riscv_core_i (
    .clk(clk), .rst_n(rst_n), .fetch_enable_i(fetch_enable_i),
    .boot_addr_i(AP_BOOT_ROM_BASE + 48'h80),
    .debug_halt_req_i(1'b0), .debug_resume_req_i(1'b0),
    .debug_halted_o(), .debug_running_o(), .debug_pc_o(), .debug_cause_o(),
    .debug_reg_req_valid_i(1'b0), .debug_reg_write_i(1'b0),
    .debug_reg_addr_i('0), .debug_reg_wdata_i('0),
    .debug_reg_rdata_o(), .debug_reg_error_o(),
    .imem_req_o(imem_req), .imem_ready_i(imem_ready), .imem_addr_o(imem_addr),
    .imem_rvalid_i(imem_rvalid), .imem_rdata_i(imem_rdata),
    .data_req_o(data_req), .data_addr_o(data_addr), .data_wdata_o(data_wdata),
    .data_we_o(data_we), .data_be_o(data_be), .data_atomic_op_o(data_atomic_op),
    .data_atomic_aq_o(data_atomic_aq), .data_atomic_rl_o(data_atomic_rl),
    .data_resp_valid_i(data_resp_valid), .data_rdata_i(data_rdata), .data_err_i(data_err),
    .data_fence_o(data_fence), .data_fence_done_i(data_fence_done),
    .data_fence_err_i(data_fence_err),
    .lmem_req_o(), .lmem_addr_o(), .lmem_accept_i(1'b0),
    .lmem_resp_valid_i(1'b0), .lmem_rdata_i('0), .lmem_err_i(1'b0),
    .mtime_i(mtime_i), .irq_i(irq_i), .wfi_wake_i(|irq_i), .wfi_sleep_o()
  );

  // -------------------------------------------------------------------------
  // CPU data routing and cache maintenance
  // -------------------------------------------------------------------------
  dcache_cpu_router dcache_cpu_router_i (
    .clk(clk), .rst_n(rst_n),
    .cpu_req_i(data_req), .cpu_addr_i(data_addr), .cpu_wdata_i(data_wdata),
    .cpu_we_i(data_we), .cpu_be_i(data_be), .cpu_atomic_op_i(data_atomic_op),
    .cpu_resp_valid_o(data_resp_valid), .cpu_rdata_o(data_rdata), .cpu_err_o(data_err),
    .cache_req_o(dcache_cpu_req), .cache_addr_o(dcache_cpu_addr),
    .cache_wdata_o(dcache_cpu_wdata), .cache_we_o(dcache_cpu_we),
    .cache_be_o(dcache_cpu_be), .cache_atomic_op_o(dcache_cpu_atomic_op),
    .cache_resp_valid_i(dcache_cpu_resp_valid), .cache_rdata_i(dcache_cpu_rdata),
    .cache_err_i(dcache_cpu_err),
    .uncached_req_o(uncached_cpu_req), .uncached_addr_o(uncached_cpu_addr),
    .uncached_wdata_o(uncached_cpu_wdata), .uncached_we_o(uncached_cpu_we),
    .uncached_be_o(uncached_cpu_be), .uncached_resp_valid_i(uncached_cpu_resp_valid),
    .uncached_rdata_i(uncached_cpu_rdata), .uncached_err_i(uncached_cpu_err)
  );

  dcache dcache_i (
    .clk(clk), .rst_n(rst_n),
    .cpu_req_i(dcache_cpu_req), .cpu_addr_i(dcache_cpu_addr),
    .cpu_wdata_i(dcache_cpu_wdata), .cpu_we_i(dcache_cpu_we),
    .cpu_be_i(dcache_cpu_be), .cpu_atomic_op_i(dcache_cpu_atomic_op),
    .cpu_resp_valid_o(dcache_cpu_resp_valid), .cpu_rdata_o(dcache_cpu_rdata),
    .cpu_err_o(dcache_cpu_err),
    .flush_i(data_fence), .flush_done_o(dcache_flush_done), .flush_err_o(dcache_flush_err),
    .line_req_o(dcache_line_req), .line_we_o(dcache_line_we),
    .line_addr_o(dcache_line_addr), .line_wdata_o(dcache_line_wdata),
    .line_resp_valid_i(dcache_line_resp_valid), .line_rdata_i(dcache_line_rdata),
    .line_err_i(dcache_line_err)
  );
  // The core emits one memory-system fence handshake for FENCE and FENCE.I.
  // Conservatively invalidate I-Cache for both forms only after dirty D-Cache
  // lines are globally visible; this is stronger than FENCE and provides the
  // required FENCE.I ordering.
  assign data_fence_done = dcache_flush_done && icache_invalidate_done;
  assign data_fence_err = dcache_flush_err;

  cache_axi4_line_adapter icache_axi_adapter_i (
    .clk(clk), .rst_n(rst_n),
    .line_req_i(icache_line_req), .line_we_i(1'b0), .line_addr_i(icache_line_addr),
    .line_wdata_i('0), .line_resp_valid_o(icache_line_resp_valid),
    .line_rdata_o(icache_line_rdata), .line_err_o(icache_line_err),
    .m_axi_awid_o(icache_awid), .m_axi_awaddr_o(icache_awaddr),
    .m_axi_awlen_o(icache_awlen), .m_axi_awsize_o(icache_awsize),
    .m_axi_awburst_o(icache_awburst), .m_axi_awcache_o(icache_awcache),
    .m_axi_awvalid_o(icache_awvalid), .m_axi_awready_i(icache_awready),
    .m_axi_wdata_o(icache_wdata), .m_axi_wstrb_o(icache_wstrb),
    .m_axi_wlast_o(icache_wlast), .m_axi_wvalid_o(icache_wvalid), .m_axi_wready_i(icache_wready),
    .m_axi_bid_i(icache_bid), .m_axi_bresp_i(icache_bresp),
    .m_axi_bvalid_i(icache_bvalid), .m_axi_bready_o(icache_bready),
    .m_axi_arid_o(icache_arid), .m_axi_araddr_o(icache_araddr),
    .m_axi_arlen_o(icache_arlen), .m_axi_arsize_o(icache_arsize),
    .m_axi_arburst_o(icache_arburst), .m_axi_arcache_o(icache_arcache),
    .m_axi_arvalid_o(icache_arvalid), .m_axi_arready_i(icache_arready),
    .m_axi_rid_i(icache_rid), .m_axi_rdata_i(icache_rdata), .m_axi_rresp_i(icache_rresp),
    .m_axi_rlast_i(icache_rlast), .m_axi_rvalid_i(icache_rvalid), .m_axi_rready_o(icache_rready)
  );

  cache_axi4_axi_bus_master icache_axi_bus_master_i (
    .axi_awid_i(icache_awid), .axi_awaddr_i(icache_awaddr), .axi_awlen_i(icache_awlen),
    .axi_awsize_i(icache_awsize), .axi_awburst_i(icache_awburst), .axi_awcache_i(icache_awcache),
    .axi_awvalid_i(icache_awvalid), .axi_awready_o(icache_awready),
    .axi_wdata_i(icache_wdata), .axi_wstrb_i(icache_wstrb), .axi_wlast_i(icache_wlast),
    .axi_wvalid_i(icache_wvalid), .axi_wready_o(icache_wready),
    .axi_bid_o(icache_bid), .axi_bresp_o(icache_bresp), .axi_bvalid_o(icache_bvalid), .axi_bready_i(icache_bready),
    .axi_arid_i(icache_arid), .axi_araddr_i(icache_araddr), .axi_arlen_i(icache_arlen),
    .axi_arsize_i(icache_arsize), .axi_arburst_i(icache_arburst), .axi_arcache_i(icache_arcache),
    .axi_arvalid_i(icache_arvalid), .axi_arready_o(icache_arready),
    .axi_rid_o(icache_rid), .axi_rdata_o(icache_rdata), .axi_rresp_o(icache_rresp),
    .axi_rlast_o(icache_rlast), .axi_rvalid_o(icache_rvalid), .axi_rready_i(icache_rready),
    .m_axi_o(mem_axi_o[0])
  );

  cache_axi4_line_adapter dcache_axi_adapter_i (
    .clk(clk), .rst_n(rst_n),
    .line_req_i(dcache_line_req), .line_we_i(dcache_line_we),
    .line_addr_i(dcache_line_addr), .line_wdata_i(dcache_line_wdata),
    .line_resp_valid_o(dcache_line_resp_valid), .line_rdata_o(dcache_line_rdata),
    .line_err_o(dcache_line_err),
    .m_axi_awid_o(dcache_awid), .m_axi_awaddr_o(dcache_awaddr),
    .m_axi_awlen_o(dcache_awlen), .m_axi_awsize_o(dcache_awsize),
    .m_axi_awburst_o(dcache_awburst), .m_axi_awcache_o(dcache_awcache),
    .m_axi_awvalid_o(dcache_awvalid), .m_axi_awready_i(dcache_awready),
    .m_axi_wdata_o(dcache_wdata), .m_axi_wstrb_o(dcache_wstrb),
    .m_axi_wlast_o(dcache_wlast), .m_axi_wvalid_o(dcache_wvalid), .m_axi_wready_i(dcache_wready),
    .m_axi_bid_i(dcache_bid), .m_axi_bresp_i(dcache_bresp),
    .m_axi_bvalid_i(dcache_bvalid), .m_axi_bready_o(dcache_bready),
    .m_axi_arid_o(dcache_arid), .m_axi_araddr_o(dcache_araddr),
    .m_axi_arlen_o(dcache_arlen), .m_axi_arsize_o(dcache_arsize),
    .m_axi_arburst_o(dcache_arburst), .m_axi_arcache_o(dcache_arcache),
    .m_axi_arvalid_o(dcache_arvalid), .m_axi_arready_i(dcache_arready),
    .m_axi_rid_i(dcache_rid), .m_axi_rdata_i(dcache_rdata), .m_axi_rresp_i(dcache_rresp),
    .m_axi_rlast_i(dcache_rlast), .m_axi_rvalid_i(dcache_rvalid), .m_axi_rready_o(dcache_rready)
  );

  ap_uncached_axi_master uncached_axi_master_i (
    .clk(clk), .rst_n(rst_n), .cpu_req_i(uncached_cpu_req),
    .cpu_addr_i(uncached_cpu_addr), .cpu_wdata_i(uncached_cpu_wdata),
    .cpu_we_i(uncached_cpu_we), .cpu_be_i(uncached_cpu_be),
    .cpu_resp_valid_o(uncached_cpu_resp_valid), .cpu_rdata_o(uncached_cpu_rdata),
    .cpu_err_o(uncached_cpu_err),
    .m_axi_awid_o(uncached_awid), .m_axi_awaddr_o(uncached_awaddr),
    .m_axi_awlen_o(uncached_awlen), .m_axi_awsize_o(uncached_awsize),
    .m_axi_awburst_o(uncached_awburst), .m_axi_awcache_o(uncached_awcache),
    .m_axi_awvalid_o(uncached_awvalid), .m_axi_awready_i(uncached_awready),
    .m_axi_wdata_o(uncached_wdata), .m_axi_wstrb_o(uncached_wstrb),
    .m_axi_wlast_o(uncached_wlast), .m_axi_wvalid_o(uncached_wvalid), .m_axi_wready_i(uncached_wready),
    .m_axi_bid_i(uncached_bid), .m_axi_bresp_i(uncached_bresp),
    .m_axi_bvalid_i(uncached_bvalid), .m_axi_bready_o(uncached_bready),
    .m_axi_arid_o(uncached_arid), .m_axi_araddr_o(uncached_araddr),
    .m_axi_arlen_o(uncached_arlen), .m_axi_arsize_o(uncached_arsize),
    .m_axi_arburst_o(uncached_arburst), .m_axi_arcache_o(uncached_arcache),
    .m_axi_arvalid_o(uncached_arvalid), .m_axi_arready_i(uncached_arready),
    .m_axi_rid_i(uncached_rid), .m_axi_rdata_i(uncached_rdata), .m_axi_rresp_i(uncached_rresp),
    .m_axi_rlast_i(uncached_rlast), .m_axi_rvalid_i(uncached_rvalid), .m_axi_rready_o(uncached_rready)
  );

  cache_axi4_axi_bus_master dcache_axi_bus_master_i (
    .axi_awid_i(dcache_awid), .axi_awaddr_i(dcache_awaddr), .axi_awlen_i(dcache_awlen),
    .axi_awsize_i(dcache_awsize), .axi_awburst_i(dcache_awburst), .axi_awcache_i(dcache_awcache),
    .axi_awvalid_i(dcache_awvalid), .axi_awready_o(dcache_awready),
    .axi_wdata_i(dcache_wdata), .axi_wstrb_i(dcache_wstrb), .axi_wlast_i(dcache_wlast),
    .axi_wvalid_i(dcache_wvalid), .axi_wready_o(dcache_wready),
    .axi_bid_o(dcache_bid), .axi_bresp_o(dcache_bresp), .axi_bvalid_o(dcache_bvalid), .axi_bready_i(dcache_bready),
    .axi_arid_i(dcache_arid), .axi_araddr_i(dcache_araddr), .axi_arlen_i(dcache_arlen),
    .axi_arsize_i(dcache_arsize), .axi_arburst_i(dcache_arburst), .axi_arcache_i(dcache_arcache),
    .axi_arvalid_i(dcache_arvalid), .axi_arready_o(dcache_arready),
    .axi_rid_o(dcache_rid), .axi_rdata_o(dcache_rdata), .axi_rresp_o(dcache_rresp),
    .axi_rlast_o(dcache_rlast), .axi_rvalid_o(dcache_rvalid), .axi_rready_i(dcache_rready),
    .m_axi_o(mem_axi_o[1])
  );

  cache_axi4_axi_bus_master periph_axi_bus_master_i (
    .axi_awid_i(uncached_awid), .axi_awaddr_i(uncached_awaddr), .axi_awlen_i(uncached_awlen),
    .axi_awsize_i(uncached_awsize), .axi_awburst_i(uncached_awburst), .axi_awcache_i(uncached_awcache),
    .axi_awvalid_i(uncached_awvalid), .axi_awready_o(uncached_awready),
    .axi_wdata_i(uncached_wdata), .axi_wstrb_i(uncached_wstrb), .axi_wlast_i(uncached_wlast),
    .axi_wvalid_i(uncached_wvalid), .axi_wready_o(uncached_wready),
    .axi_bid_o(uncached_bid), .axi_bresp_o(uncached_bresp), .axi_bvalid_o(uncached_bvalid), .axi_bready_i(uncached_bready),
    .axi_arid_i(uncached_arid), .axi_araddr_i(uncached_araddr), .axi_arlen_i(uncached_arlen),
    .axi_arsize_i(uncached_arsize), .axi_arburst_i(uncached_arburst), .axi_arcache_i(uncached_arcache),
    .axi_arvalid_i(uncached_arvalid), .axi_arready_o(uncached_arready),
    .axi_rid_o(uncached_rid), .axi_rdata_o(uncached_rdata), .axi_rresp_o(uncached_rresp),
    .axi_rlast_o(uncached_rlast), .axi_rvalid_o(uncached_rvalid), .axi_rready_i(uncached_rready),
    .m_axi_o(periph_axi_o)
  );

endmodule
