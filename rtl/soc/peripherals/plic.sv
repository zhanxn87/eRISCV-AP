// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// AP PLIC APB slave: 32 global interrupt sources, one hart, and architecturally distinct
// M-mode and S-mode contexts.  Context 0 is M and context 1 is S, using the
// standard enable and threshold/claim register strides.
module plic #(
  parameter int unsigned NUM_SOURCES = 32,
  parameter int unsigned PRIORITY_BITS = 3,
  parameter logic [31:0] BASE_ADDR = 32'h0c00_0000
) (
  input logic clk,
  input logic rst_n,

  // APB slave interface
  input logic psel_i,
  input logic penable_i,
  input logic pwrite_i,
  input logic [31:0] paddr_i,
  input logic [31:0] pwdata_i,
  input logic [3:0] pstrb_i,
  output logic pready_o,
  output logic [31:0] prdata_o,
  output logic pslverr_o,

  input logic [NUM_SOURCES-1:0] src_i,
  output logic meip_o,
  output logic seip_o
);

  localparam int unsigned NUM_CONTEXTS = 2;
  localparam int unsigned ID_WIDTH = $clog2(NUM_SOURCES + 1);
  localparam int unsigned SOURCE_WORDS = (NUM_SOURCES / 32) + 1;
  localparam int unsigned SOURCE_WORD_INDEX_WIDTH =
      (SOURCE_WORDS <= 1) ? 1 : $clog2(SOURCE_WORDS);
  localparam int unsigned CONTEXT_INDEX_WIDTH = $clog2(NUM_CONTEXTS);
  localparam logic [31:0] PENDING_BASE = 32'h0000_1000;
  localparam logic [31:0] ENABLE_BASE = 32'h0000_2000;
  localparam logic [31:0] ENABLE_CONTEXT_STRIDE = 32'h0000_0080;
  localparam logic [31:0] CONTEXT_BASE = 32'h0020_0000;
  localparam logic [31:0] CONTEXT_STRIDE = 32'h0000_1000;
  localparam logic [31:0] WINDOW_BYTES = 32'h0040_0000;

  logic [31:0] local_addr;
  logic in_window;
  logic priority_access;
  logic pending_access;
  logic enable_access;
  logic threshold_access;
  logic claim_access;
  logic valid_access;
  logic [ID_WIDTH-1:0] priority_id;
  logic [SOURCE_WORD_INDEX_WIDTH-1:0] pending_word;
  logic [SOURCE_WORD_INDEX_WIDTH-1:0] enable_word;
  logic [CONTEXT_INDEX_WIDTH-1:0] enable_context;
  logic [CONTEXT_INDEX_WIDTH-1:0] context_index;

  logic [PRIORITY_BITS-1:0] priority_q [0:NUM_SOURCES];
  logic [PRIORITY_BITS-1:0] priority_d [0:NUM_SOURCES];
  logic [NUM_SOURCES:0] pending_q;
  logic [NUM_SOURCES:0] pending_d;
  logic [NUM_SOURCES:0] enable_q [0:NUM_CONTEXTS-1];
  logic [NUM_SOURCES:0] enable_d [0:NUM_CONTEXTS-1];
  logic [NUM_SOURCES:0] in_service_q;
  logic [NUM_SOURCES:0] in_service_d;
  logic [PRIORITY_BITS-1:0] threshold_q [0:NUM_CONTEXTS-1];
  logic [PRIORITY_BITS-1:0] threshold_d [0:NUM_CONTEXTS-1];
  logic [ID_WIDTH-1:0] highest_id [0:NUM_CONTEXTS-1];
  logic [31:0] enable_write_data;
  logic [31:0] priority_write_data;
  logic [31:0] threshold_write_data;
  logic claim_read;
  logic claim_complete;

  function automatic logic [31:0] merge_bytes(
    input logic [31:0] old_value,
    input logic [31:0] new_value,
    input logic [3:0] byte_enable
  );
    logic [31:0] value;
    begin
      value = old_value;
      for (int byte_index = 0; byte_index < 4; byte_index++) begin
        if (byte_enable[byte_index])
          value[byte_index * 8 +: 8] = new_value[byte_index * 8 +: 8];
      end
      return value;
    end
  endfunction

  function automatic logic [31:0] source_word(
    input logic [NUM_SOURCES:0] sources,
    input int unsigned word_index
  );
    logic [31:0] value;
    begin
      value = '0;
      for (int source_id = 1; source_id <= NUM_SOURCES; source_id++) begin
        if ((source_id / 32) == word_index)
          value[source_id % 32] = sources[source_id];
      end
      return value;
    end
  endfunction

  logic apb_access;

  assign apb_access = psel_i && penable_i;
  assign local_addr = paddr_i - BASE_ADDR;
  assign in_window = (paddr_i >= BASE_ADDR) && (paddr_i < (BASE_ADDR + WINDOW_BYTES));
  assign priority_id = local_addr[ID_WIDTH+1:2];
  assign pending_word = local_addr[2 +: SOURCE_WORD_INDEX_WIDTH];
  assign enable_word = local_addr[2 +: SOURCE_WORD_INDEX_WIDTH];
  assign enable_context = CONTEXT_INDEX_WIDTH'(
      (local_addr - ENABLE_BASE) / ENABLE_CONTEXT_STRIDE);
  assign context_index = CONTEXT_INDEX_WIDTH'(
      (local_addr - CONTEXT_BASE) / CONTEXT_STRIDE);
  assign priority_access = in_window && (local_addr <= (NUM_SOURCES * 4)) &&
                           (local_addr[1:0] == 2'b00);
  assign pending_access = in_window && (local_addr >= PENDING_BASE) &&
                          (local_addr < (PENDING_BASE + SOURCE_WORDS * 4)) &&
                          (local_addr[1:0] == 2'b00);
  assign enable_access = in_window && (local_addr >= ENABLE_BASE) &&
                         (local_addr < (ENABLE_BASE + NUM_CONTEXTS * ENABLE_CONTEXT_STRIDE)) &&
                         (int'(enable_word) < SOURCE_WORDS) && (local_addr[1:0] == 2'b00);
  assign threshold_access = in_window && (local_addr >= CONTEXT_BASE) &&
                            (local_addr < (CONTEXT_BASE + NUM_CONTEXTS * CONTEXT_STRIDE)) &&
                            ((local_addr % CONTEXT_STRIDE) == 32'h0);
  assign claim_access = in_window && (local_addr >= CONTEXT_BASE) &&
                        (local_addr < (CONTEXT_BASE + NUM_CONTEXTS * CONTEXT_STRIDE)) &&
                        ((local_addr % CONTEXT_STRIDE) == 32'h4);
  assign valid_access = priority_access || pending_access || enable_access ||
                        threshold_access || claim_access;
  assign pready_o = 1'b1;
  assign pslverr_o = apb_access && !valid_access;
  assign claim_read = apb_access && !pwrite_i && claim_access;
  assign claim_complete = apb_access && pwrite_i && claim_access &&
                          (pwdata_i != 32'd0) && (pwdata_i <= NUM_SOURCES);
  assign meip_o = highest_id[0] != '0;
  assign seip_o = highest_id[1] != '0;
  assign enable_write_data = merge_bytes(
      source_word(enable_q[enable_context], int'(enable_word)), pwdata_i, pstrb_i);

  always_comb begin
    prdata_o = '0;
    if (priority_access)
      prdata_o = {{(32-PRIORITY_BITS){1'b0}}, priority_q[priority_id]};
    else if (pending_access)
      prdata_o = source_word(pending_q, int'(pending_word));
    else if (enable_access)
      prdata_o = source_word(enable_q[enable_context], int'(enable_word));
    else if (threshold_access)
      prdata_o = {{(32-PRIORITY_BITS){1'b0}}, threshold_q[context_index]};
    else if (claim_access)
      prdata_o = {{(32-ID_WIDTH){1'b0}}, highest_id[context_index]};
  end

  always_comb begin
    for (int ctx = 0; ctx < NUM_CONTEXTS; ctx++) begin
      highest_id[ctx] = '0;
      for (int source_id = 1; source_id <= NUM_SOURCES; source_id++) begin
        if (pending_q[source_id] && enable_q[ctx][source_id] &&
            !in_service_q[source_id] &&
            (priority_q[source_id] > threshold_q[ctx]) &&
            ((highest_id[ctx] == '0) ||
             (priority_q[source_id] > priority_q[highest_id[ctx]]) ||
             ((priority_q[source_id] == priority_q[highest_id[ctx]]) &&
              (source_id < highest_id[ctx])))) begin
          highest_id[ctx] = ID_WIDTH'(source_id);
        end
      end
    end
  end

  always_comb begin
    for (int source_id = 0; source_id <= NUM_SOURCES; source_id++)
      priority_d[source_id] = priority_q[source_id];
    pending_d = pending_q;
    in_service_d = in_service_q;
    for (int ctx = 0; ctx < NUM_CONTEXTS; ctx++) begin
      enable_d[ctx] = enable_q[ctx];
      threshold_d[ctx] = threshold_q[ctx];
    end
    priority_write_data = '0;
    threshold_write_data = '0;

    for (int source_id = 1; source_id <= NUM_SOURCES; source_id++) begin
      if (src_i[source_id - 1] && !in_service_q[source_id])
        pending_d[source_id] = 1'b1;
    end

    if (apb_access && pwrite_i && priority_access) begin
      priority_write_data = merge_bytes(
          {{(32-PRIORITY_BITS){1'b0}}, priority_q[priority_id]}, pwdata_i, pstrb_i);
      priority_d[priority_id] = priority_write_data[PRIORITY_BITS-1:0];
    end
    if (apb_access && pwrite_i && enable_access) begin
      for (int source_id = 1; source_id <= NUM_SOURCES; source_id++) begin
        if ((source_id / 32) == int'(enable_word))
          enable_d[enable_context][source_id] = enable_write_data[source_id % 32];
      end
    end
    if (apb_access && pwrite_i && threshold_access) begin
      threshold_write_data = merge_bytes(
          {{(32-PRIORITY_BITS){1'b0}}, threshold_q[context_index]}, pwdata_i, pstrb_i);
      threshold_d[context_index] = threshold_write_data[PRIORITY_BITS-1:0];
    end
    if (claim_read && (highest_id[context_index] != '0)) begin
      pending_d[highest_id[context_index]] = 1'b0;
      in_service_d[highest_id[context_index]] = 1'b1;
    end
    if (claim_complete)
      in_service_d[pwdata_i[ID_WIDTH-1:0]] = 1'b0;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int source_id = 0; source_id <= NUM_SOURCES; source_id++)
        priority_q[source_id] <= '0;
      pending_q <= '0;
      in_service_q <= '0;
      for (int ctx = 0; ctx < NUM_CONTEXTS; ctx++) begin
        enable_q[ctx] <= '0;
        threshold_q[ctx] <= '0;
      end
    end else begin
      for (int source_id = 0; source_id <= NUM_SOURCES; source_id++)
        priority_q[source_id] <= priority_d[source_id];
      pending_q <= pending_d;
      in_service_q <= in_service_d;
      for (int ctx = 0; ctx < NUM_CONTEXTS; ctx++) begin
        enable_q[ctx] <= enable_d[ctx];
        threshold_q[ctx] <= threshold_d[ctx];
      end
    end
  end

endmodule
