// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// Verification-only AXI4 memory slave for AP cache-line traffic.
//
// Dense mode preserves the original backdoor-visible `mem` array. Sparse mode
// stores only touched physical cache lines in an associative array keyed by the
// full physical line address, so high DDR addresses do not alias and a 2 GiB
// aperture does not allocate 2 GiB of simulator memory. The model supports
// multiple queued read/write bursts, configurable address-channel stalls and
// read latency, but deliberately does not model DDR PHY timing or MIG training.
module axi4_line_mem #(
  parameter int unsigned PADDR_W_P = 48,
  parameter int unsigned AXI_DATA_W_P = 64,
  parameter int unsigned AXI_ID_W_P = 4,
  parameter int unsigned LINE_BYTES_P = 64,
  parameter int unsigned LINE_ADDR_W_P = 10,
  parameter bit SPARSE_P = 1'b0,
  parameter int unsigned MAX_READ_TXNS_P = 1,
  parameter int unsigned MAX_WRITE_TXNS_P = 1,
  parameter int unsigned READ_LATENCY_P = 0,
  parameter int unsigned AR_STALL_CYCLES_P = 0,
  parameter int unsigned AW_STALL_CYCLES_P = 0,
  parameter bit READ_ERROR_ENABLE_P = 1'b0,
  parameter logic [PADDR_W_P-1:0] READ_ERROR_ADDR_P = '0,
  parameter bit WRITE_ERROR_ENABLE_P = 1'b0,
  parameter logic [PADDR_W_P-1:0] WRITE_ERROR_ADDR_P = '0
) (
  input logic clk,
  input logic rst_n,

  AXI_BUS.Slave s_axi_i
);

  localparam int unsigned LINE_BITS_P = LINE_BYTES_P * 8;
  localparam int unsigned OFFSET_W = $clog2(LINE_BYTES_P);
  localparam int unsigned AXI_BYTES_P = AXI_DATA_W_P / 8;
  localparam logic [2:0] AXI_SIZE_P = 3'($clog2(AXI_BYTES_P));
  localparam int unsigned READ_DELAY_W =
      (READ_LATENCY_P > 0) ? $clog2(READ_LATENCY_P + 1) : 1;
  localparam int unsigned STALL_W =
      ((AR_STALL_CYCLES_P > AW_STALL_CYCLES_P) ?
       ((AR_STALL_CYCLES_P > 0) ? $clog2(AR_STALL_CYCLES_P + 1) : 1) :
       ((AW_STALL_CYCLES_P > 0) ? $clog2(AW_STALL_CYCLES_P + 1) : 1));
  localparam logic [1:0] AXI_RESP_OKAY = 2'b00;
  localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;
  localparam logic [1:0] AXI_BURST_FIXED = 2'b00;
  localparam logic [1:0] AXI_BURST_INCR = 2'b01;

  // Kept for existing dense-model backdoor preload/inspection users.
  (* ram_style = "block", ramstyle = "no_rw_check" *)
  logic [LINE_BITS_P-1:0] mem [0:(1 << LINE_ADDR_W_P)-1];

  // Sparse entries are keyed by the complete physical line address. The
  // simulator grows this map only for lines that software or AXI traffic uses.
  logic [LINE_BITS_P-1:0] sparse_mem [longint unsigned];

  logic read_valid_q [0:MAX_READ_TXNS_P-1];
  logic [PADDR_W_P-1:0] read_addr_q [0:MAX_READ_TXNS_P-1];
  logic [7:0] read_len_q [0:MAX_READ_TXNS_P-1];
  logic [2:0] read_size_q [0:MAX_READ_TXNS_P-1];
  logic [1:0] read_burst_q [0:MAX_READ_TXNS_P-1];
  logic [AXI_ID_W_P-1:0] read_id_q [0:MAX_READ_TXNS_P-1];
  logic read_error_q [0:MAX_READ_TXNS_P-1];
  logic [8:0] read_beat_q [0:MAX_READ_TXNS_P-1];
  logic [READ_DELAY_W-1:0] read_delay_q [0:MAX_READ_TXNS_P-1];
  integer read_rr_q;
  logic read_emit_active_q;
  integer read_emit_slot_q;
  integer read_free_slot;
  integer read_ready_slot;

  logic [PADDR_W_P-1:0] write_addr_q [0:MAX_WRITE_TXNS_P-1];
  logic [7:0] write_len_q [0:MAX_WRITE_TXNS_P-1];
  logic [2:0] write_size_q [0:MAX_WRITE_TXNS_P-1];
  logic [1:0] write_burst_q [0:MAX_WRITE_TXNS_P-1];
  logic [AXI_ID_W_P-1:0] write_id_q [0:MAX_WRITE_TXNS_P-1];
  logic write_error_q [0:MAX_WRITE_TXNS_P-1];
  logic [8:0] write_beat_q [0:MAX_WRITE_TXNS_P-1];
  integer write_head_q;
  integer write_tail_q;
  integer write_count_q;

  logic [STALL_W-1:0] ar_stall_q;
  logic [STALL_W-1:0] aw_stall_q;
  logic read_error_enable_q;
  logic [PADDR_W_P-1:0] read_error_addr_q;
  logic write_error_enable_q;
  logic [PADDR_W_P-1:0] write_error_addr_q;
  integer byte_lane;

  function automatic longint unsigned line_key(
    input logic [PADDR_W_P-1:0] byte_addr
  );
    line_key = longint'($unsigned(byte_addr)) >> OFFSET_W;
  endfunction

  function automatic logic [LINE_ADDR_W_P-1:0] dense_index(
    input logic [PADDR_W_P-1:0] byte_addr
  );
    dense_index = byte_addr[OFFSET_W +: LINE_ADDR_W_P];
  endfunction

  function automatic logic [LINE_BITS_P-1:0] load_line(
    input logic [PADDR_W_P-1:0] byte_addr
  );
    longint unsigned key;
    begin
      if (SPARSE_P) begin
        key = line_key(byte_addr);
        if (sparse_mem.exists(key) != 0)
          load_line = sparse_mem[key];
        else
          load_line = '0;
      end else begin
        load_line = mem[dense_index(byte_addr)];
      end
    end
  endfunction

  task automatic store_line(
    input logic [PADDR_W_P-1:0] byte_addr,
    input logic [LINE_BITS_P-1:0] line_data
  );
    longint unsigned key;
    begin
      if (SPARSE_P) begin
        key = line_key(byte_addr);
        sparse_mem[key] = line_data;
      end else begin
        mem[dense_index(byte_addr)] = line_data;
      end
    end
  endtask

  // Public TB helpers. In sparse mode these retain the complete physical
  // address; in dense mode they preserve legacy low-index behavior.
  task automatic preload_line(
    input logic [PADDR_W_P-1:0] byte_addr,
    input logic [LINE_BITS_P-1:0] line_data
  );
    store_line(byte_addr, line_data);
  endtask

  task automatic read_line(
    input logic [PADDR_W_P-1:0] byte_addr,
    output logic [LINE_BITS_P-1:0] line_data
  );
    line_data = load_line(byte_addr);
  endtask

  function automatic logic [PADDR_W_P-1:0] burst_addr(
    input logic [PADDR_W_P-1:0] addr,
    input logic [8:0] beat,
    input logic [2:0] size,
    input logic [1:0] burst
  );
    begin
      unique case (burst)
        AXI_BURST_FIXED: burst_addr = addr;
        AXI_BURST_INCR:  burst_addr = addr + (PADDR_W_P'(beat) << size);
        default:         burst_addr = addr + (PADDR_W_P'(beat) << size);
      endcase
    end
  endfunction

  function automatic logic bad_attributes(
    input logic [PADDR_W_P-1:0] addr,
    input logic [2:0] size,
    input logic [1:0] burst
  );
    bad_attributes = (size != AXI_SIZE_P) ||
                     ((burst != AXI_BURST_FIXED) && (burst != AXI_BURST_INCR)) ||
                     (addr[AXI_SIZE_P-1:0] != '0);
  endfunction

  function automatic logic [AXI_DATA_W_P-1:0] load_beat(
    input logic [PADDR_W_P-1:0] addr,
    input logic [8:0] beat,
    input logic [2:0] size,
    input logic [1:0] burst
  );
    logic [PADDR_W_P-1:0] beat_addr;
    logic [LINE_BITS_P-1:0] line_data;
    int unsigned line_offset;
    begin
      beat_addr = burst_addr(addr, beat, size, burst);
      line_data = load_line(beat_addr);
      line_offset = int'(beat_addr[OFFSET_W-1:0]);
      if ((line_offset + AXI_BYTES_P) <= LINE_BYTES_P)
        load_beat = line_data[line_offset * 8 +: AXI_DATA_W_P];
      else
        load_beat = '0;
    end
  endfunction

  task automatic store_beat(
    input logic [PADDR_W_P-1:0] addr,
    input logic [8:0] beat,
    input logic [2:0] size,
    input logic [1:0] burst,
    input logic [AXI_DATA_W_P-1:0] wdata,
    input logic [AXI_BYTES_P-1:0] wstrb
  );
    logic [PADDR_W_P-1:0] beat_addr;
    logic [LINE_BITS_P-1:0] line_data;
    int unsigned line_offset;
    begin
      beat_addr = burst_addr(addr, beat, size, burst);
      line_data = load_line(beat_addr);
      line_offset = int'(beat_addr[OFFSET_W-1:0]);
      if ((line_offset + AXI_BYTES_P) <= LINE_BYTES_P) begin
        for (byte_lane = 0; byte_lane < AXI_BYTES_P; byte_lane = byte_lane + 1)
          if (wstrb[byte_lane])
            line_data[(line_offset + byte_lane) * 8 +: 8] =
                wdata[byte_lane * 8 +: 8];
        store_line(beat_addr, line_data);
      end
    end
  endtask

  function automatic integer find_free_read();
    integer slot;
    begin
      find_free_read = -1;
      for (slot = 0; slot < MAX_READ_TXNS_P; slot = slot + 1)
        if (!read_valid_q[slot] && (find_free_read == -1))
          find_free_read = slot;
    end
  endfunction

  function automatic integer find_ready_read(input integer start_slot);
    integer offset;
    integer slot;
    begin
      find_ready_read = -1;
      for (offset = 0; offset < MAX_READ_TXNS_P; offset = offset + 1) begin
        slot = start_slot + offset;
        if (slot >= MAX_READ_TXNS_P)
          slot = slot - MAX_READ_TXNS_P;
        if (read_valid_q[slot] && (read_delay_q[slot] == '0) &&
            (find_ready_read == -1))
          find_ready_read = slot;
      end
    end
  endfunction

  function automatic integer next_write_slot(input integer slot);
    if (slot == MAX_WRITE_TXNS_P - 1)
      next_write_slot = 0;
    else
      next_write_slot = slot + 1;
  endfunction

  always_comb begin
    read_free_slot = find_free_read();
    if (read_emit_active_q)
      read_ready_slot = read_emit_slot_q;
    else
      read_ready_slot = find_ready_read(read_rr_q);
  end

  assign s_axi_i.ar_ready = (read_free_slot >= 0) && (ar_stall_q == '0);
  assign s_axi_i.aw_ready = (write_count_q < MAX_WRITE_TXNS_P) &&
                            (aw_stall_q == '0);
  assign s_axi_i.w_ready = (write_count_q != 0) &&
                           !(s_axi_i.b_valid &&
                             (write_beat_q[write_head_q] ==
                              {1'b0, write_len_q[write_head_q]}));

  initial begin
    if ((LINE_BITS_P % AXI_DATA_W_P) != 0)
      $fatal(1, "axi4_line_mem: line width must be an integer number of AXI beats");
    if (MAX_READ_TXNS_P == 0 || MAX_WRITE_TXNS_P == 0)
      $fatal(1, "axi4_line_mem: transaction queue depths must be nonzero");
    read_error_enable_q = READ_ERROR_ENABLE_P;
    read_error_addr_q = READ_ERROR_ADDR_P;
    write_error_enable_q = WRITE_ERROR_ENABLE_P;
    write_error_addr_q = WRITE_ERROR_ADDR_P;
    void'($value$plusargs("axi_read_error_addr=%h", read_error_addr_q));
    if ($test$plusargs("axi_read_error_addr"))
      read_error_enable_q = 1'b1;
    void'($value$plusargs("axi_write_error_addr=%h", write_error_addr_q));
    if ($test$plusargs("axi_write_error_addr"))
      write_error_enable_q = 1'b1;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    integer slot;
    logic write_last;
    logic write_error_next;
    if (!rst_n) begin
      for (slot = 0; slot < MAX_READ_TXNS_P; slot = slot + 1) begin
        read_valid_q[slot] <= 1'b0;
        read_addr_q[slot] <= '0;
        read_len_q[slot] <= '0;
        read_size_q[slot] <= '0;
        read_burst_q[slot] <= '0;
        read_id_q[slot] <= '0;
        read_error_q[slot] <= 1'b0;
        read_beat_q[slot] <= '0;
        read_delay_q[slot] <= '0;
      end
      for (slot = 0; slot < MAX_WRITE_TXNS_P; slot = slot + 1) begin
        write_addr_q[slot] <= '0;
        write_len_q[slot] <= '0;
        write_size_q[slot] <= '0;
        write_burst_q[slot] <= '0;
        write_id_q[slot] <= '0;
        write_error_q[slot] <= 1'b0;
        write_beat_q[slot] <= '0;
      end
      read_rr_q <= 0;
      read_emit_active_q <= 1'b0;
      read_emit_slot_q <= 0;
      write_head_q <= 0;
      write_tail_q <= 0;
      write_count_q <= 0;
      ar_stall_q <= '0;
      aw_stall_q <= '0;
      s_axi_i.r_id <= '0;
      s_axi_i.r_data <= '0;
      s_axi_i.r_resp <= AXI_RESP_OKAY;
      s_axi_i.r_last <= 1'b0;
      s_axi_i.r_user <= '0;
      s_axi_i.r_valid <= 1'b0;
      s_axi_i.b_id <= '0;
      s_axi_i.b_resp <= AXI_RESP_OKAY;
      s_axi_i.b_user <= '0;
      s_axi_i.b_valid <= 1'b0;
    end else begin
      if (ar_stall_q != '0)
        ar_stall_q <= ar_stall_q - 1'b1;
      if (aw_stall_q != '0)
        aw_stall_q <= aw_stall_q - 1'b1;

      for (slot = 0; slot < MAX_READ_TXNS_P; slot = slot + 1)
        if (read_valid_q[slot] && (read_delay_q[slot] != '0))
          read_delay_q[slot] <= read_delay_q[slot] - 1'b1;

      if (s_axi_i.ar_valid && s_axi_i.ar_ready) begin
        read_valid_q[read_free_slot] <= 1'b1;
        read_addr_q[read_free_slot] <= s_axi_i.ar_addr;
        read_len_q[read_free_slot] <= s_axi_i.ar_len;
        read_size_q[read_free_slot] <= s_axi_i.ar_size;
        read_burst_q[read_free_slot] <= s_axi_i.ar_burst;
        read_id_q[read_free_slot] <= s_axi_i.ar_id;
        read_error_q[read_free_slot] <=
            bad_attributes(s_axi_i.ar_addr, s_axi_i.ar_size, s_axi_i.ar_burst) ||
            (read_error_enable_q && (s_axi_i.ar_addr == read_error_addr_q));
        read_beat_q[read_free_slot] <= '0;
        read_delay_q[read_free_slot] <= READ_DELAY_W'(READ_LATENCY_P);
        ar_stall_q <= STALL_W'(AR_STALL_CYCLES_P);
      end

      if (s_axi_i.r_valid && s_axi_i.r_ready) begin
        s_axi_i.r_valid <= 1'b0;
        if (s_axi_i.r_last) begin
          read_valid_q[read_emit_slot_q] <= 1'b0;
          read_emit_active_q <= 1'b0;
          if (read_emit_slot_q == MAX_READ_TXNS_P - 1)
            read_rr_q <= 0;
          else
            read_rr_q <= read_emit_slot_q + 1;
        end else begin
          read_beat_q[read_emit_slot_q] <=
              read_beat_q[read_emit_slot_q] + 1'b1;
        end
      end else if (!s_axi_i.r_valid && (read_ready_slot >= 0)) begin
        s_axi_i.r_id <= read_id_q[read_ready_slot];
        s_axi_i.r_data <= load_beat(read_addr_q[read_ready_slot],
                                    read_beat_q[read_ready_slot],
                                    read_size_q[read_ready_slot],
                                    read_burst_q[read_ready_slot]);
        s_axi_i.r_resp <= read_error_q[read_ready_slot] ? AXI_RESP_SLVERR :
                                                           AXI_RESP_OKAY;
        s_axi_i.r_last <= read_beat_q[read_ready_slot] ==
                           {1'b0, read_len_q[read_ready_slot]};
        s_axi_i.r_user <= '0;
        s_axi_i.r_valid <= 1'b1;
        read_emit_active_q <= 1'b1;
        read_emit_slot_q <= read_ready_slot;
      end

      if (s_axi_i.aw_valid && s_axi_i.aw_ready) begin
        write_addr_q[write_tail_q] <= s_axi_i.aw_addr;
        write_len_q[write_tail_q] <= s_axi_i.aw_len;
        write_size_q[write_tail_q] <= s_axi_i.aw_size;
        write_burst_q[write_tail_q] <= s_axi_i.aw_burst;
        write_id_q[write_tail_q] <= s_axi_i.aw_id;
        write_error_q[write_tail_q] <=
            bad_attributes(s_axi_i.aw_addr, s_axi_i.aw_size, s_axi_i.aw_burst) ||
            (write_error_enable_q && (s_axi_i.aw_addr == write_error_addr_q));
        write_beat_q[write_tail_q] <= '0;
        write_tail_q <= next_write_slot(write_tail_q);
        write_count_q <= write_count_q + 1;
        aw_stall_q <= STALL_W'(AW_STALL_CYCLES_P);
      end

      if (s_axi_i.w_valid && s_axi_i.w_ready) begin
        write_last = write_beat_q[write_head_q] ==
                     {1'b0, write_len_q[write_head_q]};
        write_error_next = write_error_q[write_head_q] ||
                           (s_axi_i.w_last != write_last);
        if (!write_error_q[write_head_q])
          store_beat(write_addr_q[write_head_q],
                     write_beat_q[write_head_q],
                     write_size_q[write_head_q],
                     write_burst_q[write_head_q],
                     s_axi_i.w_data,
                     s_axi_i.w_strb);
        if (write_last) begin
          s_axi_i.b_id <= write_id_q[write_head_q];
          s_axi_i.b_resp <= write_error_next ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
          s_axi_i.b_user <= '0;
          s_axi_i.b_valid <= 1'b1;
          write_head_q <= next_write_slot(write_head_q);
          write_count_q <= write_count_q - 1;
        end else begin
          write_beat_q[write_head_q] <= write_beat_q[write_head_q] + 1'b1;
          write_error_q[write_head_q] <= write_error_next;
        end
      end

      if (s_axi_i.b_valid && s_axi_i.b_ready)
        s_axi_i.b_valid <= 1'b0;
    end
  end

endmodule
