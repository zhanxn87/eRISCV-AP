// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

import riscv_pkg::*;

// Memory stage for load/store formatting and MEM/WB packet assembly.
// Loads are aligned and sign/zero extended here so WB only performs register writeback.
module mem_stage #(
  parameter int unsigned PADDR_W_P = CORE_XLEN
) (
  // Clock and reset
  input  logic        clk,
  input  logic        rst_n,

  // EX/MEM -> MEM/WB pipeline boundary
  input  var ex_mem_t ex_mem_i,
  input  var mem_wb_t mem_wb_fwd_i,
  input  logic        ex_mem_en_i,

  // Normal D-bus transaction (MEM <-> SoC). A request is accepted when
  // data_req_o and data_req_ready_i are both asserted.
  input  logic        data_req_ready_i,
  input  logic        data_resp_valid_i,
  input  logic [63:0] data_rdata_i,
  input  logic        data_err_i,
  input  logic        data_page_fault_i,
  // Serialized FENCE completion. data_fence_o remains asserted until the
  // memory system reports that all prior writes are globally observable.
  output logic        data_fence_o,
  input  logic        data_fence_done_i,
  input  logic        data_fence_err_i,
  output logic        data_req_o,
  output logic [PADDR_W_P-1:0] data_addr_o,
  output logic [63:0] data_wdata_o,
  output logic        data_we_o,
  output logic [7:0]  data_be_o,
  output atomic_op_e  data_atomic_op_o,
  output logic        data_atomic_aq_o,
  output logic        data_atomic_rl_o,

  // A completed data fault is transported as a CONTROL_EXCEPTION packet by
  // this stage. EX uses its cause to redirect and flush younger work.
  output logic        mem_fault_valid_o,
  output xlen_t       mem_fault_cause_o,

  output logic        load_result_bypass_valid_o,
  output logic [4:0]  load_result_bypass_rd_addr_o,
  output xlen_t       load_result_bypass_data_o,

  // MEM pipeline completion
  output logic        mem_wait_o,
  output mem_wb_t     mem_wb_o
);

  // MEM/WB packet and normal D-bus outstanding-request state. MEM/WB is the
  // architectural completion boundary and advances every cycle; MEM stalls
  // keep its packet invalid until a response is available.
  mem_wb_t mem_wb_d;
  logic mem_pending_q;

  // Address-derived load/store formatting
  logic [2:0] addr_offset;
  xlen_t       store_data;
  logic [63:0] store_wdata;
  logic [7:0] store_be;
  logic [7:0] load_be;
  xlen_t       load_data;
  logic mem_op;
  logic fence_response;
  logic load_store_data_match;

  // Normal D-bus response selection
  logic mem_response_valid;
  logic [63:0] response_rdata;
  logic [63:0] shifted_load_data;
  logic response_err;
  logic mem_fault_valid;
  logic mem_fault_store;

  // ---------------------------------------------------------------------------
  // Memory operation and response qualification
  // ---------------------------------------------------------------------------
  assign addr_offset = ex_mem_i.data_addr[2:0];
  assign mem_op = ex_mem_i.valid & (ex_mem_i.mem_load | ex_mem_i.mem_store |
                                    (ex_mem_i.atomic_op != ATOMIC_NONE) |
                                    ex_mem_i.fence);
  // Responses are registered: an accepted request enters mem_pending_q
  // before the fabric may return its response. This avoids a combinational
  // response loop through a shared instruction/data arbiter.
  assign fence_response = ex_mem_i.valid && ex_mem_i.fence && data_fence_done_i;
  assign mem_response_valid = ex_mem_i.fence ? fence_response :
                              (data_resp_valid_i & mem_pending_q);
  assign response_rdata = ex_mem_i.fence ? '0 : data_rdata_i;
  assign response_err = ex_mem_i.fence ? data_fence_err_i : data_err_i;
  assign mem_fault_valid = mem_response_valid && !ex_mem_i.fence && response_err;
  assign mem_fault_store = ex_mem_i.mem_store ||
                           ((ex_mem_i.atomic_op != ATOMIC_NONE) &&
                            (ex_mem_i.atomic_op != ATOMIC_LR));
  assign mem_fault_valid_o = mem_fault_valid;
  always_comb begin
    if (data_page_fault_i)
      mem_fault_cause_o = mem_fault_store ? xlen_t'(15) : xlen_t'(13);
    else
      mem_fault_cause_o = mem_fault_store ? xlen_t'(7) : xlen_t'(5);
  end
  assign shifted_load_data = response_rdata >> (addr_offset * 8);
  // Preserve MEM/WB as the architectural completion boundary while exposing
  // a successfully completed load only to the dedicated branch/store-data
  // bypasses. Pending responses keep EX frozen through mem_wait_o.
  assign load_result_bypass_valid_o = mem_response_valid &&
                                      ex_mem_i.mem_load && !response_err;
  assign load_result_bypass_rd_addr_o = ex_mem_i.rd_addr;
  assign load_result_bypass_data_o = load_data;
  assign mem_wait_o = mem_op && !mem_response_valid;

  // ---------------------------------------------------------------------------
  // Store formatting
  // Store byte enables and write-data packing are derived from the effective
  // address so the backing SRAM model can stay word-oriented.
  // ---------------------------------------------------------------------------
  // A load-to-store-data dependency is carried through EX/MEM as metadata.
  // Select the registered load result here, one stage later, so the completed
  // response does not feed the EX operand/address/control cone.
  assign load_store_data_match = ex_mem_i.valid && ex_mem_i.mem_store &&
                                 ex_mem_i.load_store_data_bypass &&
                                 mem_wb_fwd_i.valid && mem_wb_fwd_i.rd_we &&
                                 (mem_wb_fwd_i.rd_addr != 5'd0) &&
                                 (mem_wb_fwd_i.rd_addr == ex_mem_i.store_rs2_addr);
  assign store_data = load_store_data_match ? mem_wb_fwd_i.wb_data :
                                              ex_mem_i.store_data;

  // Load extraction
  // ---------------------------------------------------------------------------
  always_comb begin
    store_wdata = store_data;
    store_be    = 8'b0000_0000;

    unique case (ex_mem_i.mem_type)
      3'b000: begin
        store_wdata = {8{store_data[7:0]}} << (addr_offset * 8);
        store_be    = 8'b0000_0001 << addr_offset;
      end
      3'b001: begin
        store_wdata = {4{store_data[15:0]}} << (addr_offset * 8);
        store_be    = 8'b0000_0011 << addr_offset;
      end
      default: begin
        store_wdata = {2{store_data[31:0]}} << (addr_offset * 8);
        store_be    = 8'b0000_1111 << addr_offset;
      end
      3'b011: begin
        store_wdata = store_data;
        store_be    = 8'b1111_1111;
      end
    endcase
  end

  // Preserve the access byte mask on reads as well. The SoC boundary adapter
  // needs it to select one or two legacy 32-bit words without issuing a second
  // side-effecting MMIO read for an LB/LH/LW.
  always_comb begin
    unique case (ex_mem_i.mem_type)
      3'b000, 3'b100: load_be = 8'b0000_0001 << addr_offset;
      3'b001, 3'b101: load_be = 8'b0000_0011 << addr_offset;
      3'b010, 3'b110: load_be = 8'b0000_1111 << addr_offset;
      default:         load_be = 8'b1111_1111;
    endcase
  end

  always_comb begin
    unique case (ex_mem_i.mem_type)
      3'b000: begin // LB
        load_data = {{56{shifted_load_data[7]}}, shifted_load_data[7:0]};
      end
      3'b001: begin // LH
        load_data = {{48{shifted_load_data[15]}}, shifted_load_data[15:0]};
      end
      3'b010: begin // LW
        load_data = {{32{shifted_load_data[31]}}, shifted_load_data[31:0]};
      end
      3'b011: begin // LD
        load_data = response_rdata;
      end
      3'b100: begin // LBU
        load_data = {56'd0, shifted_load_data[7:0]};
      end
      3'b101: begin // LHU
        load_data = {48'd0, shifted_load_data[15:0]};
      end
      3'b110: begin // LWU
        load_data = {32'd0, shifted_load_data[31:0]};
      end
      default: begin
        load_data = response_rdata;
      end
    endcase
  end


  // ---------------------------------------------------------------------------
  // D-bus interface
  // A request remains valid until it is accepted, then remains pending until
  // its response. Keeping valid independent of ready avoids a core/fabric
  // combinational loop when the fabric arbitrates instruction and data ports.
  // ---------------------------------------------------------------------------
  assign data_fence_o = ex_mem_i.valid && ex_mem_i.fence;
  assign data_req_o   = mem_op && !ex_mem_i.fence && !mem_pending_q;
  assign data_addr_o  = ex_mem_i.data_addr[PADDR_W_P-1:0];
  assign data_wdata_o = store_wdata;
  assign data_we_o    = mem_op && ex_mem_i.mem_store;
  assign data_be_o    = (ex_mem_i.mem_store || (ex_mem_i.atomic_op != ATOMIC_NONE)) ? store_be : load_be;
  assign data_atomic_op_o = ex_mem_i.atomic_op;
  assign data_atomic_aq_o = ex_mem_i.atomic_aq;
  assign data_atomic_rl_o = ex_mem_i.atomic_rl;

  // ---------------------------------------------------------------------------
  // MEM/WB packet construction
  // Preserve WB-aligned PC/instruction alongside writeback data so the SoC TB
  // can keep trace checking without adding debug ports to riscv_soc.
  always_comb begin
    mem_wb_d = '0;
    mem_wb_d.valid   = ex_mem_i.valid & (!mem_op | mem_response_valid);
    mem_wb_d.control_source      = ex_mem_i.control_source;
    mem_wb_d.pc      = ex_mem_i.pc;
    mem_wb_d.instr   = ex_mem_i.instr;
    mem_wb_d.control_trap_pc    = ex_mem_i.control_trap_pc;
    mem_wb_d.control_trap_cause = ex_mem_i.control_trap_cause;
    mem_wb_d.control_trap_value = ex_mem_i.control_trap_value;
    mem_wb_d.control_debug_dpc  = ex_mem_i.control_debug_dpc;
    mem_wb_d.control_debug_cause = ex_mem_i.control_debug_cause;
    mem_wb_d.control_sfence_vma_vaddr = ex_mem_i.control_sfence_vma_vaddr;
    mem_wb_d.control_sfence_vma_asid = ex_mem_i.control_sfence_vma_asid;
    mem_wb_d.wb_data = ex_mem_i.mem_load ? load_data : ex_mem_i.ex_result;
    mem_wb_d.rd_addr = ex_mem_i.rd_addr;
    mem_wb_d.rd_we   = ex_mem_i.rd_we & !response_err;
    // M2 extends the common MEM/WB packet with FPR writeback and FCSR flags.
    mem_wb_d.fp_write = ex_mem_i.fp_write & !response_err;
    mem_wb_d.fp_dirty = ex_mem_i.fp_dirty & !response_err;
    mem_wb_d.fp_dst_fmt = ex_mem_i.fp_dst_fmt;
    mem_wb_d.fp_rd_addr = ex_mem_i.fp_rd_addr;
    mem_wb_d.fp_fflags = ex_mem_i.fp_fflags;
    if (mem_fault_valid) begin
      mem_wb_d.control_source = CONTROL_EXCEPTION;
      mem_wb_d.control_trap_pc = ex_mem_i.pc;
      mem_wb_d.control_trap_cause = mem_fault_cause_o;
      mem_wb_d.control_trap_value = ex_mem_i.data_addr;
      mem_wb_d.rd_we = 1'b0;
      mem_wb_d.fp_write = 1'b0;
      mem_wb_d.fp_dirty = 1'b0;
    end
  end

  // ---------------------------------------------------------------------------
  // Sequential MEM state
  // MEM/WB advances every cycle; mem_wb_d marks incomplete operations invalid.
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mem_pending_q <= 1'b0;
      mem_wb_o <= '0;
    end else begin
      if (data_req_o && data_req_ready_i && !data_resp_valid_i) begin
        mem_pending_q <= 1'b1;
      end else if (mem_response_valid) begin
        mem_pending_q <= 1'b0;
      end

      mem_wb_o <= mem_wb_d;
    end
  end

endmodule
