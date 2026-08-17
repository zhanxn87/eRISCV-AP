// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

import riscv_pkg::*;

// One-outstanding-operation adapter between the RV64F/D core and locked CVFPU.
// Registered ingress and response boundaries isolate the core issue and
// completion cones from the vendor IP. Every RV64F/D operation therefore takes
// one additional start cycle and one additional completion cycle.
module fpu_adapter (
  // Clock and reset
  input  logic         clk,
  input  logic         rst_n,

  // Core issue channel
  input  logic         issue_valid_i,
  input  fp_issue_t    issue_i,
  output logic         issue_ready_o,

  // Core cancellation and completion channel
  input  logic         flush_i,
  output logic         complete_valid_o,
  output fp_complete_t complete_o,
  input  logic         complete_ready_i,
  output logic         busy_o
);

  // Scalar RV64D pipeline: retain registered arithmetic/convert execution and
  // use CVFPU's FP64-capable THMULTI div/sqrt implementation. DOTP/MXDOTP
  // operation groups remain disabled.
  localparam fpnew_pkg::fpu_implementation_t AP_RV64D_IMPLEMENTATION = '{
    PipeRegs: '{'{default: 3}, '{default: 0}, '{default: 1},
                '{default: 2}, '{default: 0}, '{default: 0}},
    UnitTypes: '{'{default: fpnew_pkg::PARALLEL},
                 '{default: fpnew_pkg::MERGED},
                 '{default: fpnew_pkg::PARALLEL},
                 '{default: fpnew_pkg::MERGED},
                 '{default: fpnew_pkg::DISABLED},
                 '{default: fpnew_pkg::DISABLED}},
    PipeConfig: fpnew_pkg::INSIDE
  };

  // CVFPU request/response handshake
  logic        fp_in_valid;
  logic        fp_in_ready;
  logic        fp_out_valid;
  logic        fp_out_ready;
  // CVFPU result payload
  logic [63:0] fp_result;
  fpnew_pkg::status_t fp_status;
  logic [7:0]  fp_tag;
  // Registered CVFPU ingress boundary
  logic        request_valid_q;
  fp_issue_t   request_q;
  // Adapter-owned outstanding-operation completion metadata
  logic        inflight_q;
  fp_issue_t   issue_q;
  // Registered CVFPU response boundary
  logic        response_valid_q;
  logic [63:0] response_result_q;
  fpnew_pkg::status_t response_status_q;
  logic [7:0]  response_tag_q;

  assign fp_in_valid   = request_valid_q && !flush_i;
  assign issue_ready_o = !request_valid_q && !inflight_q && !flush_i;
  // Do not bypass EX/MEM readiness into CVFPU.  The response slot captures
  // every CVFPU result before it becomes visible to the core.
  assign fp_out_ready  = !response_valid_q && !flush_i;
  assign busy_o        = request_valid_q || inflight_q || response_valid_q;
  assign complete_valid_o = response_valid_q && inflight_q;

  always_comb begin
    complete_o.result    = issue_q.result_word ?
                           {{32{response_result_q[31]}}, response_result_q[31:0]} :
                           response_result_q;
    complete_o.fflags    = {response_status_q.NV, response_status_q.DZ,
                            response_status_q.OF, response_status_q.UF,
                            response_status_q.NX};
    complete_o.write_gpr = issue_q.write_gpr;
    complete_o.rd_addr   = issue_q.rd_addr;
    complete_o.tag       = response_tag_q;
  end

  fpnew_top #(
    .Features       (fpnew_pkg::RV64D),
    .Implementation (AP_RV64D_IMPLEMENTATION),
    .DivSqrtSel     (fpnew_pkg::THMULTI),
    .TagType        (logic [7:0])
  ) cvfpu_i (
    .clk_i          (clk),
    .rst_ni         (rst_n),
    .hart_id_i      (32'd0),
    .operands_i     ({request_q.operand_c, request_q.operand_b, request_q.operand_a}),
    .rnd_mode_i     (fpnew_pkg::roundmode_e'(request_q.rounding_mode)),
    .op_i           (fpnew_pkg::operation_e'(request_q.operation)),
    .op_mod_i       (request_q.operation_modifier),
    .src_fmt_i      (request_q.src_fmt == FP_FMT_D ? fpnew_pkg::FP64 : fpnew_pkg::FP32),
    .dst_fmt_i      (request_q.dst_fmt == FP_FMT_D ? fpnew_pkg::FP64 : fpnew_pkg::FP32),
    .int_fmt_i      (request_q.int_fmt_d ? fpnew_pkg::INT64 : fpnew_pkg::INT32),
    .vectorial_op_i (1'b0),
    .tag_i          (request_q.tag),
    .simd_mask_i    ('1),
    .pace_param_i   ('0),
    .pace_mode_i    ('0),
    .in_valid_i     (fp_in_valid),
    .in_ready_o     (fp_in_ready),
    // An issued scalar FP operation holds ID/EX until completion. Therefore
    // no architectural redirect or load-use bubble can
    // cancel it in flight; propagating the global ID/EX flush here creates a
    // CVFPU out_valid -> core wait/flush -> CVFPU flush combinational loop.
    // Reset remains the sole CVFPU pipeline clear.
    .flush_i        (1'b0),
    .result_o       (fp_result),
    .status_o       (fp_status),
    .tag_o          (fp_tag),
    .out_valid_o    (fp_out_valid),
    .out_ready_i    (fp_out_ready),
    .busy_o         ()
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      request_valid_q <= 1'b0;
      request_q       <= '0;
      inflight_q      <= 1'b0;
      issue_q         <= '0;
      response_valid_q <= 1'b0;
      response_result_q <= '0;
      response_status_q <= '0;
      response_tag_q    <= '0;
    end else if (flush_i) begin
      request_valid_q <= 1'b0;
      request_q       <= '0;
      inflight_q      <= 1'b0;
      issue_q         <= '0;
      response_valid_q <= 1'b0;
      response_result_q <= '0;
      response_status_q <= '0;
      response_tag_q    <= '0;
    end else begin
      if (issue_valid_i && !request_valid_q && !inflight_q) begin
        request_valid_q <= 1'b1;
        request_q       <= issue_i;
      end else if (fp_in_valid && fp_in_ready) begin
        request_valid_q <= 1'b0;
        inflight_q <= 1'b1;
        issue_q    <= request_q;
      end
      if (fp_out_valid && fp_out_ready && inflight_q) begin
        response_valid_q  <= 1'b1;
        response_result_q <= fp_result;
        response_status_q <= fp_status;
        response_tag_q    <= fp_tag;
      end else if (response_valid_q && complete_ready_i) begin
        response_valid_q <= 1'b0;
        inflight_q       <= 1'b0;
      end
    end
  end

endmodule
