// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Hart-local virtual-memory frontend. It owns translation request state, PTW
// arbitration, physical fetch/data routing, private L1 caches, and their AXI
// managers. ap_hart_tile is intentionally structural and only connects this
// frontend to riscv_core.
import ap_soc_pkg::*;
import riscv_pkg::*;
import sv39_pkg::*;

module ap_hart_memory_frontend #(
  parameter int unsigned BOOT_ROM_SIZE_BYTES_P = 64 * 1024
) (
  // Clock and reset.
  input logic clk,
  input logic rst_n,

  // Core virtual instruction port.
  input logic imem_req,
  output logic imem_ready,
  input xlen_t imem_addr,
  output logic imem_rvalid,
  output logic [31:0] imem_rdata,
  output logic imem_page_fault,
  output logic imem_access_fault,

  // Core virtual data port and fence completion.
  input logic data_req,
  output logic data_req_ready,
  input xlen_t data_addr,
  input logic [63:0] data_wdata,
  input logic data_we,
  input logic [7:0] data_be,
  input logic [3:0] data_atomic_op,
  output logic data_resp_valid,
  output logic [63:0] data_rdata,
  output logic data_err,
  output logic data_page_fault,
  input logic data_fence,
  output logic data_fence_done,
  output logic data_fence_err,

  // Hart-local translation context from the core CSR file.
  input xlen_t hart_satp,
  input privilege_mode_e hart_privilege,
  input privilege_mode_e hart_mstatus_mpp,
  input logic hart_mstatus_sum,
  input logic hart_mstatus_mxr,
  input logic hart_mstatus_mprv,
  input logic hart_sfence_vma,
  input xlen_t hart_sfence_vma_vaddr,
  input logic [15:0] hart_sfence_vma_asid,

  // Cluster-owned shared Boot ROM fetch port.
  output logic boot_imem_req_o,
  output logic [AP_PADDR_W-1:0] boot_imem_addr_o,
  input logic boot_imem_ready_i,
  input logic boot_imem_rvalid_i,
  input logic [31:0] boot_imem_rdata_i,

  // Cached DDR managers and uncached peripheral manager.
  AXI_BUS.Master mem_axi_o [1:0],
  AXI_BUS.Master periph_axi_o
);

  privilege_mode_e data_privilege;
  sv39_access_e data_access;

  // -------------------------------------------------------------------------
  // Hart-local ITLB/DTLB/PTW request state
  // -------------------------------------------------------------------------
  typedef enum logic [2:0] {
    I_IDLE,
    I_MMU_WAIT,
    I_PHYS_REQ,
    I_PHYS_WAIT,
    I_FAULT_RESP
  } i_state_e;
  typedef enum logic [2:0] {
    D_IDLE,
    D_MMU_WAIT,
    D_PHYS_REQ,
    D_PHYS_WAIT,
    D_FAULT_RESP
  } d_state_e;

  i_state_e i_state_q;
  d_state_e d_state_q;
  paddr_t i_paddr_q;
  logic i_page_fault_q, i_access_fault_q;
  paddr_t d_paddr_q;
  logic d_page_fault_q, d_access_fault_q;
  logic d_we_q;
  logic [63:0] d_wdata_q;
  logic [7:0] d_be_q;
  logic [3:0] d_atomic_op_q;

  logic mmu_i_req_valid, mmu_i_req_ready;
  logic mmu_i_resp_valid, mmu_i_resp_ready;
  paddr_t mmu_i_resp_paddr;
  logic mmu_i_resp_page_fault, mmu_i_resp_access_fault;
  logic mmu_d_req_valid, mmu_d_req_ready;
  logic mmu_d_resp_valid, mmu_d_resp_ready;
  paddr_t mmu_d_resp_paddr;
  logic mmu_d_resp_page_fault, mmu_d_resp_access_fault;
  logic mmu_pte_req_valid, mmu_pte_req_ready;
  paddr_t mmu_pte_addr;
  xlen_t mmu_pte_wdata;
  atomic_op_e mmu_pte_atomic_op;
  logic mmu_pte_resp_valid, mmu_pte_resp_err;
  xlen_t mmu_pte_resp_rdata;
  logic pte_issue, ptw_pending_q;

  // -------------------------------------------------------------------------
  // I-Cache physical request path
  // -------------------------------------------------------------------------
  logic icache_imem_req, icache_imem_ready, icache_imem_rvalid, icache_imem_err;
  logic [AP_PADDR_W-1:0] icache_imem_addr;
  logic [31:0] icache_imem_rdata;
  logic icache_invalidate_done;
  logic icache_line_req, icache_line_resp_valid, icache_line_err;
  logic [AP_PADDR_W-1:0] icache_line_addr;
  logic [511:0] icache_line_rdata;

  // -------------------------------------------------------------------------
  // D-Cache physical port, translated CPU routing, and PTW request mux
  // -------------------------------------------------------------------------
  logic dcache_router_req, dcache_router_we, dcache_router_resp_valid, dcache_router_err;
  logic [AP_PADDR_W-1:0] dcache_router_addr;
  logic [63:0] dcache_router_wdata, dcache_router_rdata;
  logic [7:0] dcache_router_be;
  logic [3:0] dcache_router_atomic_op;
  logic dcache_router_cache_resp_valid, dcache_router_cache_err;
  logic [63:0] dcache_router_cache_rdata;

  logic dcache_port_req, dcache_port_we, dcache_port_resp_valid, dcache_port_err;
  logic [AP_PADDR_W-1:0] dcache_port_addr;
  logic [63:0] dcache_port_wdata, dcache_port_rdata;
  logic [7:0] dcache_port_be;
  logic [3:0] dcache_port_atomic_op;
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
  // Hart-local Sv39 translation and physical request state
  // -------------------------------------------------------------------------
  assign data_privilege = (hart_privilege == PRIV_M && hart_mstatus_mprv) ?
                          hart_mstatus_mpp : hart_privilege;
  assign data_access = data_we ? SV39_ACCESS_STORE : SV39_ACCESS_LOAD;

  // The core only observes acceptance when the MMU controller can capture the
  // virtual request. Its one-request controller gives fetch deterministic
  // priority when both ports become ready in the same cycle.
  assign imem_ready = (i_state_q == I_IDLE) && mmu_i_req_ready;
  assign mmu_i_req_valid = imem_req && imem_ready;
  assign data_req_ready = (d_state_q == D_IDLE) && mmu_d_req_ready;
  assign mmu_d_req_valid = data_req && data_req_ready;
  assign mmu_i_resp_ready = i_state_q == I_MMU_WAIT;
  assign mmu_d_resp_ready = d_state_q == D_MMU_WAIT;

  // The PTW's PTE reads bypass virtual translation but reuse the physically
  // indexed D-Cache. A core D request is never issued while its D state owns
  // the port; an I-side miss waits until the port becomes available.
  assign mmu_pte_req_ready = !ptw_pending_q && !data_fence &&
                             ((i_state_q == I_MMU_WAIT && d_state_q == D_IDLE) ||
                              (d_state_q == D_MMU_WAIT));
  assign pte_issue = mmu_pte_req_valid && mmu_pte_req_ready;
  assign mmu_pte_resp_valid = ptw_pending_q && dcache_port_resp_valid;
  assign mmu_pte_resp_rdata = dcache_port_rdata;
  assign mmu_pte_resp_err = dcache_port_err;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ptw_pending_q <= 1'b0;
    end else begin
      if (pte_issue)
        ptw_pending_q <= 1'b1;
      else if (mmu_pte_resp_valid)
        ptw_pending_q <= 1'b0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      i_state_q <= I_IDLE;
      i_paddr_q <= '0;
      i_page_fault_q <= 1'b0;
      i_access_fault_q <= 1'b0;
    end else begin
      unique case (i_state_q)
        I_IDLE: begin
          if (mmu_i_req_valid)
            i_state_q <= I_MMU_WAIT;
        end
        I_MMU_WAIT: begin
          if (mmu_i_resp_valid && mmu_i_resp_ready) begin
            i_paddr_q <= mmu_i_resp_paddr;
            i_page_fault_q <= mmu_i_resp_page_fault;
            i_access_fault_q <= mmu_i_resp_access_fault ||
                                (!mmu_i_resp_page_fault &&
                                 !ap_addr_in_range(mmu_i_resp_paddr,
                                                   AP_BOOT_ROM_BASE,
                                                   AP_BOOT_ROM_BASE + BOOT_ROM_SIZE_BYTES_P) &&
                                 !ap_is_ddr_addr(mmu_i_resp_paddr));
            if (mmu_i_resp_page_fault || mmu_i_resp_access_fault ||
                (!ap_addr_in_range(mmu_i_resp_paddr,
                                   AP_BOOT_ROM_BASE,
                                   AP_BOOT_ROM_BASE + BOOT_ROM_SIZE_BYTES_P) &&
                 !ap_is_ddr_addr(mmu_i_resp_paddr)))
              i_state_q <= I_FAULT_RESP;
            else
              i_state_q <= I_PHYS_REQ;
          end
        end
        I_PHYS_REQ: begin
          if (ap_addr_in_range(i_paddr_q, AP_BOOT_ROM_BASE,
                               AP_BOOT_ROM_BASE + BOOT_ROM_SIZE_BYTES_P)) begin
            if (boot_imem_ready_i)
              i_state_q <= I_PHYS_WAIT;
          end else if (ap_is_ddr_addr(i_paddr_q)) begin
            if (icache_imem_ready)
              i_state_q <= I_PHYS_WAIT;
          end else begin
            i_page_fault_q <= 1'b0;
            i_access_fault_q <= 1'b1;
            i_state_q <= I_FAULT_RESP;
          end
        end
        I_PHYS_WAIT: begin
          if (boot_imem_rvalid_i || icache_imem_rvalid)
            i_state_q <= I_IDLE;
        end
        I_FAULT_RESP: i_state_q <= I_IDLE;
        default: i_state_q <= I_IDLE;
      endcase
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      d_state_q <= D_IDLE;
      d_paddr_q <= '0;
      d_page_fault_q <= 1'b0;
      d_access_fault_q <= 1'b0;
      d_we_q <= 1'b0;
      d_wdata_q <= '0;
      d_be_q <= '0;
      d_atomic_op_q <= '0;
    end else begin
      unique case (d_state_q)
        D_IDLE: begin
          if (mmu_d_req_valid) begin
            d_we_q <= data_we;
            d_wdata_q <= data_wdata;
            d_be_q <= data_be;
            d_atomic_op_q <= data_atomic_op;
            d_state_q <= D_MMU_WAIT;
          end
        end
        D_MMU_WAIT: begin
          if (mmu_d_resp_valid && mmu_d_resp_ready) begin
            d_paddr_q <= mmu_d_resp_paddr;
            d_page_fault_q <= mmu_d_resp_page_fault;
            d_access_fault_q <= mmu_d_resp_access_fault;
            d_state_q <= (mmu_d_resp_page_fault || mmu_d_resp_access_fault) ?
                         D_FAULT_RESP : D_PHYS_REQ;
          end
        end
        D_PHYS_REQ: d_state_q <= D_PHYS_WAIT;
        D_PHYS_WAIT: begin
          if (dcache_router_resp_valid)
            d_state_q <= D_IDLE;
        end
        D_FAULT_RESP: d_state_q <= D_IDLE;
        default: d_state_q <= D_IDLE;
      endcase
    end
  end

  always_comb begin
    boot_imem_req_o = 1'b0;
    boot_imem_addr_o = i_paddr_q;
    icache_imem_req = 1'b0;
    icache_imem_addr = i_paddr_q;
    imem_rvalid = 1'b0;
    imem_rdata = 32'h0000_0013;
    imem_page_fault = 1'b0;
    imem_access_fault = 1'b0;

    if (i_state_q == I_PHYS_REQ) begin
      if (ap_addr_in_range(i_paddr_q, AP_BOOT_ROM_BASE,
                           AP_BOOT_ROM_BASE + BOOT_ROM_SIZE_BYTES_P))
        boot_imem_req_o = 1'b1;
      else if (ap_is_ddr_addr(i_paddr_q))
        icache_imem_req = 1'b1;
    end else if (i_state_q == I_PHYS_WAIT) begin
      if (boot_imem_rvalid_i) begin
        imem_rvalid = 1'b1;
        imem_rdata = boot_imem_rdata_i;
      end else if (icache_imem_rvalid) begin
        imem_rvalid = 1'b1;
        imem_rdata = icache_imem_rdata;
        imem_access_fault = icache_imem_err;
      end
    end else if (i_state_q == I_FAULT_RESP) begin
      imem_rvalid = 1'b1;
      imem_page_fault = i_page_fault_q;
      imem_access_fault = i_access_fault_q;
    end
  end

  always_comb begin
    data_resp_valid = 1'b0;
    data_rdata = '0;
    data_err = 1'b0;
    data_page_fault = 1'b0;
    if (d_state_q == D_PHYS_WAIT && dcache_router_resp_valid) begin
      data_resp_valid = 1'b1;
      data_rdata = dcache_router_rdata;
      data_err = dcache_router_err;
    end else if (d_state_q == D_FAULT_RESP) begin
      data_resp_valid = 1'b1;
      data_err = 1'b1;
      data_page_fault = d_page_fault_q;
    end
  end

  sv39_mmu_ctrl mmu_ctrl_i (
    .clk(clk),
    .rst_n(rst_n),
    .flush_valid_i(hart_sfence_vma),
    .flush_vaddr_i(hart_sfence_vma_vaddr),
    .flush_asid_i(hart_sfence_vma_asid),
    .i_req_valid_i(mmu_i_req_valid),
    .i_req_ready_o(mmu_i_req_ready),
    .i_req_vaddr_i(imem_addr),
    .i_req_satp_i(hart_satp),
    .i_req_privilege_i(hart_privilege),
    .i_req_sum_i(hart_mstatus_sum),
    .i_req_mxr_i(hart_mstatus_mxr),
    .i_resp_valid_o(mmu_i_resp_valid),
    .i_resp_ready_i(mmu_i_resp_ready),
    .i_resp_paddr_o(mmu_i_resp_paddr),
    .i_resp_page_fault_o(mmu_i_resp_page_fault),
    .i_resp_access_fault_o(mmu_i_resp_access_fault),
    .d_req_valid_i(mmu_d_req_valid),
    .d_req_ready_o(mmu_d_req_ready),
    .d_req_vaddr_i(data_addr),
    .d_req_satp_i(hart_satp),
    .d_req_privilege_i(data_privilege),
    .d_req_access_i(data_access),
    .d_req_sum_i(hart_mstatus_sum),
    .d_req_mxr_i(hart_mstatus_mxr),
    .d_resp_valid_o(mmu_d_resp_valid),
    .d_resp_ready_i(mmu_d_resp_ready),
    .d_resp_paddr_o(mmu_d_resp_paddr),
    .d_resp_page_fault_o(mmu_d_resp_page_fault),
    .d_resp_access_fault_o(mmu_d_resp_access_fault),
    .pte_req_valid_o(mmu_pte_req_valid),
    .pte_req_ready_i(mmu_pte_req_ready),
    .pte_req_addr_o(mmu_pte_addr),
    .pte_req_wdata_o(mmu_pte_wdata),
    .pte_req_atomic_op_o(mmu_pte_atomic_op),
    .pte_resp_valid_i(mmu_pte_resp_valid),
    .pte_resp_rdata_i(mmu_pte_resp_rdata),
    .pte_resp_err_i(mmu_pte_resp_err)
  );

  // -------------------------------------------------------------------------
  // Private instruction cache
  // -------------------------------------------------------------------------
  icache icache_i (
    .clk(clk),
    .rst_n(rst_n),
    .cpu_req_i(icache_imem_req),
    .cpu_addr_i(icache_imem_addr),
    .invalidate_i(data_fence),
    .invalidate_done_o(icache_invalidate_done),
    .cpu_ready_o(icache_imem_ready),
    .cpu_rvalid_o(icache_imem_rvalid),
    .cpu_rdata_o(icache_imem_rdata),
    .cpu_err_o(icache_imem_err),
    .line_req_o(icache_line_req),
    .line_addr_o(icache_line_addr),
    .line_resp_valid_i(icache_line_resp_valid),
    .line_rdata_i(icache_line_rdata),
    .line_err_i(icache_line_err)
  );

  // -------------------------------------------------------------------------
  // CPU data routing and cache maintenance
  // -------------------------------------------------------------------------
  dcache_cpu_router dcache_cpu_router_i (
    .clk(clk),
    .rst_n(rst_n),
    .cpu_req_i(d_state_q == D_PHYS_REQ),
    .cpu_addr_i(d_paddr_q),
    .cpu_wdata_i(d_wdata_q),
    .cpu_we_i(d_we_q),
    .cpu_be_i(d_be_q),
    .cpu_atomic_op_i(d_atomic_op_q),
    .cpu_resp_valid_o(dcache_router_resp_valid),
    .cpu_rdata_o(dcache_router_rdata),
    .cpu_err_o(dcache_router_err),
    .cache_req_o(dcache_router_req),
    .cache_addr_o(dcache_router_addr),
    .cache_wdata_o(dcache_router_wdata),
    .cache_we_o(dcache_router_we),
    .cache_be_o(dcache_router_be),
    .cache_atomic_op_o(dcache_router_atomic_op),
    .cache_resp_valid_i(dcache_router_cache_resp_valid),
    .cache_rdata_i(dcache_router_cache_rdata),
    .cache_err_i(dcache_router_cache_err),
    .uncached_req_o(uncached_cpu_req),
    .uncached_addr_o(uncached_cpu_addr),
    .uncached_wdata_o(uncached_cpu_wdata),
    .uncached_we_o(uncached_cpu_we),
    .uncached_be_o(uncached_cpu_be),
    .uncached_resp_valid_i(uncached_cpu_resp_valid),
    .uncached_rdata_i(uncached_cpu_rdata),
    .uncached_err_i(uncached_cpu_err)
  );

  always_comb begin
    dcache_port_req = dcache_router_req;
    dcache_port_addr = dcache_router_addr;
    dcache_port_wdata = dcache_router_wdata;
    dcache_port_we = dcache_router_we;
    dcache_port_be = dcache_router_be;
    dcache_port_atomic_op = dcache_router_atomic_op;
    if (pte_issue) begin
      dcache_port_req = 1'b1;
      dcache_port_addr = mmu_pte_addr;
      dcache_port_wdata = mmu_pte_wdata;
      dcache_port_we = 1'b0;
      dcache_port_be = 8'hff;
      dcache_port_atomic_op = mmu_pte_atomic_op;
    end
  end

  // A PTW transaction owns the D-Cache response while ptw_pending_q is set.
  // The CPU router only sees responses for translated data requests.
  assign dcache_router_cache_resp_valid = dcache_port_resp_valid && !ptw_pending_q;
  assign dcache_router_cache_rdata = dcache_port_rdata;
  assign dcache_router_cache_err = dcache_port_err;

  dcache dcache_i (
    .clk(clk),
    .rst_n(rst_n),
    .cpu_req_i(dcache_port_req),
    .cpu_addr_i(dcache_port_addr),
    .cpu_wdata_i(dcache_port_wdata),
    .cpu_we_i(dcache_port_we),
    .cpu_be_i(dcache_port_be),
    .cpu_atomic_op_i(dcache_port_atomic_op),
    .cpu_resp_valid_o(dcache_port_resp_valid),
    .cpu_rdata_o(dcache_port_rdata),
    .cpu_err_o(dcache_port_err),
    .flush_i(data_fence),
    .flush_done_o(dcache_flush_done),
    .flush_err_o(dcache_flush_err),
    .line_req_o(dcache_line_req),
    .line_we_o(dcache_line_we),
    .line_addr_o(dcache_line_addr),
    .line_wdata_o(dcache_line_wdata),
    .line_resp_valid_i(dcache_line_resp_valid),
    .line_rdata_i(dcache_line_rdata),
    .line_err_i(dcache_line_err)
  );
  // The core emits one memory-system fence handshake for FENCE and FENCE.I.
  // Conservatively invalidate I-Cache for both forms only after dirty D-Cache
  // lines are globally visible; this is stronger than FENCE and provides the
  // required FENCE.I ordering.
  assign data_fence_done = dcache_flush_done && icache_invalidate_done;
  assign data_fence_err = dcache_flush_err;

  cache_axi4_line_adapter icache_axi_adapter_i (
    .clk(clk),
    .rst_n(rst_n),
    .line_req_i(icache_line_req),
    .line_we_i(1'b0),
    .line_addr_i(icache_line_addr),
    .line_wdata_i('0),
    .line_resp_valid_o(icache_line_resp_valid),
    .line_rdata_o(icache_line_rdata),
    .line_err_o(icache_line_err),
    .m_axi_o(mem_axi_o[0])
  );

  cache_axi4_line_adapter dcache_axi_adapter_i (
    .clk(clk),
    .rst_n(rst_n),
    .line_req_i(dcache_line_req),
    .line_we_i(dcache_line_we),
    .line_addr_i(dcache_line_addr),
    .line_wdata_i(dcache_line_wdata),
    .line_resp_valid_o(dcache_line_resp_valid),
    .line_rdata_o(dcache_line_rdata),
    .line_err_o(dcache_line_err),
    .m_axi_o(mem_axi_o[1])
  );

  ap_uncached_axi_master uncached_axi_master_i (
    .clk(clk),
    .rst_n(rst_n),
    .cpu_req_i(uncached_cpu_req),
    .cpu_addr_i(uncached_cpu_addr),
    .cpu_wdata_i(uncached_cpu_wdata),
    .cpu_we_i(uncached_cpu_we),
    .cpu_be_i(uncached_cpu_be),
    .cpu_resp_valid_o(uncached_cpu_resp_valid),
    .cpu_rdata_o(uncached_cpu_rdata),
    .cpu_err_o(uncached_cpu_err),
    .m_axi_o(periph_axi_o)
  );


endmodule
