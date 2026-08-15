// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

import riscv_pkg::*;

// Fetch stage with compressed-instruction (C extension) support.
// Fetches 32-bit words at word-aligned boundaries.  When the lower halfword is
// compressed (bits[1:0] != 2'b11), the upper halfword is buffered as the next
// sequential instruction without issuing a new IMEM request.  Unaligned 32-bit
// instructions (starting at PC[1]==1 with bits[17:16]==2'b11) cause a two-cycle
// compose across word boundaries.
module if_stage #(
  // Allow same-image performance A/B of the sequential upper-halfword RV32
  // prefetch. Disabling this never changes cross-word instruction assembly.
  parameter bit ENABLE_UPPER_32_PREFETCH_P = 1'b1
) (
  // Clock and reset
  input  logic        clk,
  input  logic        rst_n,

  // Fetch activation and sequential PC control
  input  logic        fetch_enable_i,
  input  xlen_t       boot_addr_i,
  input  logic        pc_en_i,

  // Redirect control
  input  logic        redirect_valid_i,
  input  xlen_t       redirect_pc_i,

  // I-bus transaction (IF <-> SoC)
  input  logic        imem_ready_i,
  input  logic        imem_rvalid_i,
  input  logic [31:0] imem_rdata_i,
  input  logic        imem_page_fault_i,
  input  logic        imem_access_fault_i,
  output logic        imem_req_o,
  output xlen_t       imem_addr_o,

  // IF/ID boundary
  input  logic        if_id_en_i,
  input  logic        if_id_flush_i,
  output if_id_t      if_id_o,

  // Fetch status and Debug halt-PC observation
  output logic        fetch_wait_o,
  output xlen_t       halt_pc_o
);

  // ---------------------------------------------------------------------------
  // Fetch transaction state
  // ---------------------------------------------------------------------------
  xlen_t       pc_q;
  xlen_t       pc_d;
  logic        boot_init_q;
  xlen_t       resp_pc_q;
  logic        req_pending_q;

  // Instruction delivery buffers. A held instruction has priority over an
  // upper-halfword instruction, which has priority over a new IMEM response.
  xlen_t       hold_pc_q;
  logic [31:0] hold_instr_q;
  logic        hold_valid_q;
  logic        hold_compressed_q;
  logic        upper_valid_q;
  logic [15:0] upper_data_q;
  xlen_t       upper_pc_q;

  // Redirect bookkeeping discards an obsolete outstanding response exactly
  // once after a redirect supersedes its request.
  logic        redirect_pending_q;
  xlen_t       redirect_pc_q;
  logic        drop_resp_q;

  // IMEM response classification and request-issue predicates
  logic        response_valid;
  logic        response_has_two_c;
  logic        response_starts_upper;
  logic        response_upper_32_prefetch;
  logic        redirect_request;
  xlen_t       request_pc;
  logic        can_issue;
  logic        issue_redirect_request;
  logic        issue_sequential_request;

  // Word-aligned I-bus address formation
  xlen_t       aligned_fetch_pc;

  // ---------------------------------------------------------------------------
  // Response and request qualification
  // ---------------------------------------------------------------------------
  // A 16-bit halfword is compressed when its low opcode bits are not 2'b11.
  function automatic logic is_c_instr(input logic [15:0] hw);
    return hw[1:0] != 2'b11;
  endfunction

  // Expose the next-instruction PC for external halt DPC capture.  When the
  // pipeline drains, pc_q holds the address of the next instruction that
  // would have been fetched — exactly what the Debug spec expects in DPC.
  assign halt_pc_o = pc_q;

  assign response_valid = req_pending_q & imem_rvalid_i;
  // Drain both compressed halfwords before accepting another fetch response.
  // Otherwise a new response can arrive while the upper halfword has priority
  // at the output, and the response for the following word is lost.
  assign response_has_two_c = response_valid && is_c_instr(imem_rdata_i[15:0]) &&
                       is_c_instr(imem_rdata_i[31:16]);
  assign response_starts_upper = response_valid && resp_pc_q[1];
  // A 32-bit instruction beginning in the response upper halfword is queued
  // into the compose buffer. The following aligned word is independent and
  // can be requested in the same cycle. C16 starts retain the conservative
  // response ordering below.
  generate
    if (ENABLE_UPPER_32_PREFETCH_P) begin : g_upper_32_prefetch
      assign response_upper_32_prefetch = response_starts_upper &&
                                           !is_c_instr(imem_rdata_i[31:16]) &&
                                           if_id_en_i && !if_id_flush_i &&
                                           !drop_resp_q && !redirect_request;
    end else begin : g_no_upper_32_prefetch
      assign response_upper_32_prefetch = 1'b0;
    end
  endgenerate
  assign redirect_request = redirect_pending_q | redirect_valid_i;
  assign request_pc = redirect_valid_i ? redirect_pc_i : redirect_pc_q;
  assign can_issue = fetch_enable_i & !boot_init_q && !hold_valid_q &&
                     (!req_pending_q | imem_rvalid_i) &&
                     !response_has_two_c &&
                     (!response_starts_upper || response_upper_32_prefetch) &&
                     !(upper_valid_q && !is_c_instr(upper_data_q) && response_valid &&
                       (!if_id_en_i || is_c_instr(imem_rdata_i[31:16])));
  assign issue_redirect_request = can_issue & redirect_request & imem_ready_i;
  assign issue_sequential_request = can_issue & !redirect_request & pc_en_i & imem_ready_i;

  // I-bus requests are always word-aligned, including redirects to a C
  // halfword; resp_pc_q retains the original halfword address for delivery.
  assign aligned_fetch_pc = redirect_request ? {request_pc[CORE_XLEN-1:2], 2'b00} :
                                                {pc_q[CORE_XLEN-1:2], 2'b00};

  // ---------------------------------------------------------------------------
  // I-bus interface
  // ---------------------------------------------------------------------------
  assign imem_req_o  = can_issue & (redirect_request | pc_en_i);
  assign imem_addr_o = aligned_fetch_pc;
  assign fetch_wait_o = (req_pending_q & !imem_rvalid_i) |
                        (fetch_enable_i & !hold_valid_q & !req_pending_q & !imem_ready_i);

  // `pc_q` has several delivery and request-lifecycle update causes. Compute
  // their explicit priority once, then assign the state element in one place.
  always_comb begin
    pc_d = pc_q;

    if (issue_redirect_request) begin
      pc_d = request_pc + xlen_t'(4);
    end else if (issue_sequential_request) begin
      pc_d = pc_q + xlen_t'(4);
    end else if (!redirect_valid_i && !if_id_flush_i &&
                 upper_valid_q && if_id_en_i && !drop_resp_q &&
                 is_c_instr(upper_data_q)) begin
      pc_d = upper_pc_q + xlen_t'(2);
    end else if (!redirect_valid_i && !if_id_flush_i &&
                 response_valid && !drop_resp_q && resp_pc_q[1]) begin
      pc_d = resp_pc_q + xlen_t'(2);
    end
  end

  // ---------------------------------------------------------------------------
  // Sequential fetch state
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc_q               <= '0;
      resp_pc_q          <= '0;
      boot_init_q        <= 1'b1;
      req_pending_q      <= 1'b0;
      hold_pc_q          <= '0;
      hold_instr_q       <= 32'h0000_0013;
      hold_valid_q       <= 1'b0;
      hold_compressed_q  <= 1'b0;
      redirect_pending_q <= 1'b0;
      redirect_pc_q      <= '0;
      drop_resp_q        <= 1'b0;
      upper_valid_q      <= 1'b0;
      upper_data_q       <= 16'h0000;
      upper_pc_q         <= '0;
      if_id_o            <= '0;
    end else if (boot_init_q) begin
      // Asynchronous reset may only apply constant values. Load the runtime
      // boot vector synchronously before the first request is allowed.
      pc_q               <= boot_addr_i;
      resp_pc_q          <= boot_addr_i;
      redirect_pc_q      <= boot_addr_i;
      boot_init_q        <= 1'b0;
    end else begin
      pc_q <= pc_d;
      // Redirect/flush dominates all instruction delivery in this cycle.
      if (redirect_valid_i) begin
        hold_valid_q      <= 1'b0;
        upper_valid_q     <= 1'b0;
        if_id_o           <= '0;
        redirect_pc_q     <= redirect_pc_i;
        if (!issue_redirect_request) begin
          redirect_pending_q <= 1'b1;
          if (req_pending_q && !imem_rvalid_i) begin
            drop_resp_q <= 1'b1;
          end
        end
      end else if (if_id_flush_i) begin
        hold_valid_q  <= 1'b0;
        upper_valid_q <= 1'b0;
        if_id_o       <= '0;
      end else begin
        // A fault response is an instruction packet, not a synthetic NOP.
        // It must precede any buffered halfword from the failed fetch stream.
        if (response_valid && (imem_page_fault_i || imem_access_fault_i) &&
            !drop_resp_q && if_id_en_i) begin
          if_id_o.valid                    <= 1'b1;
          if_id_o.pc                       <= resp_pc_q;
          if_id_o.instr                    <= 32'h0000_0013;
          if_id_o.compressed               <= 1'b0;
          if_id_o.instruction_page_fault   <= imem_page_fault_i;
          if_id_o.instruction_access_fault <= imem_access_fault_i;
          hold_valid_q                     <= 1'b0;
          upper_valid_q                    <= 1'b0;
        // Priority: hold buffer > upper-halfword buffer > IMEM response
        end else if (hold_valid_q && if_id_en_i) begin
          if_id_o.instruction_page_fault   <= 1'b0;
          if_id_o.instruction_access_fault <= 1'b0;
          if_id_o.valid      <= 1'b1;
          if_id_o.pc         <= hold_pc_q;
          if_id_o.instr      <= hold_instr_q;
          if_id_o.compressed <= hold_compressed_q;
          hold_valid_q       <= 1'b0;
        end else if (upper_valid_q && !is_c_instr(upper_data_q) &&
                     response_valid && if_id_en_i && !drop_resp_q) begin
          // Complete a 32-bit instruction that starts in the upper halfword.
          if_id_o.valid      <= 1'b1;
          if_id_o.pc         <= upper_pc_q;
          if_id_o.instr      <= {imem_rdata_i[15:0], upper_data_q};
          if_id_o.compressed               <= 1'b0;
          if_id_o.instruction_page_fault   <= 1'b0;
          if_id_o.instruction_access_fault <= 1'b0;
          // The response upper halfword starts the next sequential instruction.
          // Preserve it while request lifecycle concurrently advances to the
          // following word; otherwise an RVC/uncompressed stream re-reads words.
          upper_valid_q      <= 1'b1;
          upper_data_q       <= imem_rdata_i[31:16];
          upper_pc_q         <= upper_pc_q + xlen_t'(4);
        end else if (upper_valid_q && if_id_en_i && !drop_resp_q) begin
          // Upper halfword from a previous fetch.
          if (is_c_instr(upper_data_q)) begin
            if_id_o.valid      <= 1'b1;
            if_id_o.pc         <= upper_pc_q;
            if_id_o.instr      <= {16'b0, upper_data_q};
            if_id_o.compressed               <= 1'b1;
            if_id_o.instruction_page_fault   <= 1'b0;
            if_id_o.instruction_access_fault <= 1'b0;
            upper_valid_q      <= 1'b0;
          end else begin
            // Wait for the following word so the upper-halfword instruction
            // can be assembled in the branch above.
            if_id_o.valid <= 1'b0;
          end
        end else if (response_valid && !drop_resp_q && if_id_en_i) begin
          if (resp_pc_q[1]) begin
            // A redirect can legally target a halfword address with RVC.
            if (is_c_instr(imem_rdata_i[31:16])) begin
              if_id_o.valid      <= 1'b1;
              if_id_o.pc         <= resp_pc_q;
              if_id_o.instr      <= {16'b0, imem_rdata_i[31:16]};
              if_id_o.compressed               <= 1'b1;
              if_id_o.instruction_page_fault   <= 1'b0;
              if_id_o.instruction_access_fault <= 1'b0;
              upper_valid_q      <= 1'b0;
            end else begin
              upper_valid_q <= 1'b1;
              upper_data_q  <= imem_rdata_i[31:16];
              upper_pc_q    <= resp_pc_q;
              if_id_o.valid <= 1'b0;
            end
          end else if (is_c_instr(imem_rdata_i[15:0])) begin
            // Lower half is compressed; buffer upper half for next cycle.
            if_id_o.valid      <= 1'b1;
            if_id_o.pc         <= resp_pc_q;
            if_id_o.instr      <= {16'b0, imem_rdata_i[15:0]};
            if_id_o.compressed               <= 1'b1;
            if_id_o.instruction_page_fault   <= 1'b0;
            if_id_o.instruction_access_fault <= 1'b0;
            upper_valid_q      <= 1'b1;
            upper_data_q       <= imem_rdata_i[31:16];
            upper_pc_q         <= resp_pc_q + xlen_t'(2);
          end else begin
            // 32-bit instruction at a word boundary.
            if_id_o.valid      <= 1'b1;
            if_id_o.pc         <= resp_pc_q;
            if_id_o.instr      <= imem_rdata_i;
            if_id_o.compressed               <= 1'b0;
            if_id_o.instruction_page_fault   <= 1'b0;
            if_id_o.instruction_access_fault <= 1'b0;
            upper_valid_q      <= 1'b0;
          end
        end else if (upper_valid_q && !is_c_instr(upper_data_q) &&
                     response_valid && !drop_resp_q) begin
          // A stalled ID stage must retain the cross-word instruction as one
          // 32-bit operation; the response low halfword is not a C instruction.
          hold_valid_q      <= 1'b1;
          hold_pc_q         <= upper_pc_q;
          hold_instr_q      <= {imem_rdata_i[15:0], upper_data_q};
          hold_compressed_q <= 1'b0;
          // Retain the next instruction's first halfword alongside the held
          // composed instruction. No new request is issued while ID is held.
          upper_valid_q     <= 1'b1;
          upper_data_q      <= imem_rdata_i[31:16];
          upper_pc_q        <= upper_pc_q + xlen_t'(4);
        end else if (response_valid && !drop_resp_q) begin
          // Preserve the requested halfword when a data-memory stall prevents
          // ID from accepting this instruction response.
          if (resp_pc_q[1]) begin
            if (is_c_instr(imem_rdata_i[31:16])) begin
              hold_valid_q      <= 1'b1;
              hold_pc_q         <= resp_pc_q;
              hold_instr_q      <= {16'b0, imem_rdata_i[31:16]};
              hold_compressed_q <= 1'b1;
              upper_valid_q     <= 1'b0;
            end else begin
              hold_valid_q  <= 1'b0;
              upper_valid_q <= 1'b1;
              upper_data_q  <= imem_rdata_i[31:16];
              upper_pc_q    <= resp_pc_q;
            end
          end else begin
            hold_valid_q <= 1'b1;
            hold_pc_q    <= resp_pc_q;
            if (is_c_instr(imem_rdata_i[15:0])) begin
              hold_instr_q      <= {16'b0, imem_rdata_i[15:0]};
              hold_compressed_q <= 1'b1;
              upper_valid_q     <= 1'b1;
              upper_data_q      <= imem_rdata_i[31:16];
              upper_pc_q        <= resp_pc_q + xlen_t'(2);
            end else begin
              hold_instr_q      <= imem_rdata_i;
              hold_compressed_q <= 1'b0;
              upper_valid_q     <= 1'b0;
            end
          end
        end else if (if_id_en_i) begin
          if_id_o.valid <= 1'b0;
        end
      end

      // Request lifecycle runs after delivery so a response can retire and a
      // replacement request can be issued in the same cycle.
      if (issue_redirect_request) begin
        resp_pc_q          <= request_pc;
        req_pending_q      <= 1'b1;
        redirect_pending_q <= 1'b0;
        upper_valid_q      <= 1'b0;
      end else if (issue_sequential_request) begin
        resp_pc_q     <= pc_q;
        req_pending_q <= 1'b1;
      end else if (response_valid) begin
        req_pending_q <= 1'b0;
      end

      if (response_valid && drop_resp_q) begin
        drop_resp_q <= 1'b0;
      end
    end
  end

endmodule
