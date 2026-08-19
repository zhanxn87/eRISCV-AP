// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// DDR-resident descriptor-ring control plane for the AP Ethernet MAC.
//
// Descriptors are 32 bytes and naturally aligned:
//   word 0: buffer physical address (bits 47:0, 8-byte aligned)
//   word 1: bits 15:0 length/capacity; bit 16 OWN; bit 17 IOC; bit 18 EOP
//   word 2: bit 0 DONE; bit 1 ERROR; bits 15:8 error; bits 31:16 actual length
//   word 3: software-owned cookie/reserved
//
// Hardware consumes [HEAD, TAIL). It writes word 2 only after the payload DMA
// operation finishes. Descriptor transactions are separate from payload DMA so
// a standard AXI mux can share the one SoC-facing AXI master port.
module ap_eth_ring_engine
  import ap_soc_pkg::*;
#(
  parameter logic [15:0] TX_MAX_BYTES_P = 16'd1536,
  parameter logic [15:0] RX_MAX_BYTES_P = 16'd2048
) (
  input logic clk,
  input logic rst_n,

  input logic tx_enable_i,
  input logic ring_reset_i,
  input logic [47:0] tx_ring_base_i,
  input logic [15:0] tx_ring_count_i,
  input logic [15:0] tx_tail_i,
  input logic tx_doorbell_i,
  output logic [15:0] tx_head_o,
  output logic tx_busy_o,

  input logic rx_enable_i,
  input logic [47:0] rx_ring_base_i,
  input logic [15:0] rx_ring_count_i,
  input logic [15:0] rx_tail_i,
  input logic rx_doorbell_i,
  output logic [15:0] rx_head_o,
  output logic rx_busy_o,

  output logic tx_launch_valid_o,
  input logic tx_launch_ready_i,
  output logic [47:0] tx_launch_addr_o,
  output logic [15:0] tx_launch_len_o,
  input logic tx_complete_valid_i,
  input logic tx_complete_error_i,

  output logic rx_arm_valid_o,
  input logic rx_arm_ready_i,
  output logic [47:0] rx_arm_addr_o,
  output logic [15:0] rx_arm_capacity_o,
  input logic rx_complete_valid_i,
  input logic [15:0] rx_complete_len_i,
  input logic rx_complete_error_i,

  output logic tx_done_o,
  output logic tx_error_o,
  output logic rx_done_o,
  output logic rx_error_o,

  AXI_BUS.Master desc_axi_o
);

  localparam logic [7:0] DESC_ERR_AXI = 8'h01;
  localparam logic [7:0] DESC_ERR_FORMAT = 8'h02;
  localparam logic [7:0] DESC_ERR_PAYLOAD = 8'h03;

  typedef enum logic [3:0] {
    ST_IDLE,
    ST_FETCH_AR,
    ST_FETCH_R,
    ST_PARSE,
    ST_TX_LAUNCH,
    ST_RX_ARM,
    ST_COMP_AW,
    ST_COMP_W,
    ST_COMP_B
  } state_t;

  state_t state_q;
  logic current_is_tx_q;
  logic [47:0] current_desc_addr_q;
  logic [63:0] desc_word0_q;
  logic [63:0] desc_word1_q;
  logic [63:0] desc_word2_q;
  logic [63:0] desc_word3_q;
  logic [1:0] fetch_count_q;
  logic fetch_error_q;
  logic current_ioc_q;
  logic [47:0] current_buffer_addr_q;
  logic [15:0] current_len_q;

  logic [47:0] tx_active_desc_addr_q;
  logic [15:0] tx_active_len_q;
  logic tx_active_ioc_q;
  logic tx_active_q;
  logic tx_completion_pending_q;
  logic tx_completion_error_q;
  logic [47:0] rx_active_desc_addr_q;
  logic rx_active_ioc_q;
  logic rx_active_q;
  logic rx_completion_pending_q;
  logic [15:0] rx_completion_len_q;
  logic rx_completion_error_q;
  logic tx_wait_owner_q;
  logic rx_wait_owner_q;

  logic completion_is_tx_q;
  logic completion_ioc_q;
  logic [15:0] completion_len_q;
  logic [7:0] completion_error_q;

  logic tx_ring_valid;
  logic rx_ring_valid;
  logic desc_own;
  logic desc_ioc;
  logic desc_eop;
  logic desc_format_valid;
  logic [63:0] completion_status_word;

  function automatic logic ring_valid(
    input logic [47:0] base,
    input logic [15:0] count,
    input logic [15:0] tail
  );
    logic [15:0] count_minus_one;
    begin
      count_minus_one = count - 16'd1;
      ring_valid = (base[4:0] == 5'b0) && (count >= 16'd2) &&
                   (count <= 16'd256) && ((count & count_minus_one) == 16'b0) &&
                   (tail < count);
    end
  endfunction

  function automatic logic [15:0] ring_next(
    input logic [15:0] index,
    input logic [15:0] count
  );
    begin
      if (index == (count - 16'd1))
        ring_next = 16'd0;
      else
        ring_next = index + 16'd1;
    end
  endfunction

  function automatic logic [47:0] ring_desc_addr(
    input logic [47:0] base,
    input logic [15:0] index
  );
    begin
      ring_desc_addr = base + ({32'b0, index} << 5);
    end
  endfunction

  assign tx_ring_valid = ring_valid(tx_ring_base_i, tx_ring_count_i, tx_tail_i);
  assign rx_ring_valid = ring_valid(rx_ring_base_i, rx_ring_count_i, rx_tail_i);
  assign desc_own = desc_word1_q[16];
  assign desc_ioc = desc_word1_q[17];
  assign desc_eop = desc_word1_q[18];
  assign desc_format_valid = (desc_word0_q[2:0] == 3'b0) && desc_eop &&
                             (desc_word1_q[15:0] != 16'd0) &&
                             (current_is_tx_q ?
                              (desc_word1_q[15:0] <= TX_MAX_BYTES_P) :
                              (desc_word1_q[15:0] <= RX_MAX_BYTES_P));
  assign completion_status_word = {
    32'b0,
    completion_len_q,
    6'b0,
    completion_error_q,
    (completion_error_q != 8'b0),
    1'b1
  };

  assign tx_busy_o = tx_active_q ||
                     ((state_q == ST_FETCH_AR || state_q == ST_FETCH_R ||
                       state_q == ST_PARSE || state_q == ST_TX_LAUNCH) &&
                      current_is_tx_q);
  assign rx_busy_o = rx_active_q ||
                     ((state_q == ST_FETCH_AR || state_q == ST_FETCH_R ||
                       state_q == ST_PARSE || state_q == ST_RX_ARM) &&
                      !current_is_tx_q);
  assign tx_launch_valid_o = (state_q == ST_TX_LAUNCH);
  assign tx_launch_addr_o = current_buffer_addr_q;
  assign tx_launch_len_o = current_len_q;
  assign rx_arm_valid_o = (state_q == ST_RX_ARM);
  assign rx_arm_addr_o = current_buffer_addr_q;
  assign rx_arm_capacity_o = current_len_q;

  always_comb begin
    desc_axi_o.aw_id = '0;
    desc_axi_o.aw_addr = current_desc_addr_q + 48'd16;
    desc_axi_o.aw_len = 8'd0;
    desc_axi_o.aw_size = 3'd3;
    desc_axi_o.aw_burst = 2'b01;
    desc_axi_o.aw_lock = 1'b0;
    desc_axi_o.aw_cache = 4'b0011;
    desc_axi_o.aw_prot = 3'b010;
    desc_axi_o.aw_qos = '0;
    desc_axi_o.aw_region = '0;
    desc_axi_o.aw_atop = '0;
    desc_axi_o.aw_user = '0;
    desc_axi_o.aw_valid = (state_q == ST_COMP_AW);
    desc_axi_o.w_data = completion_status_word;
    desc_axi_o.w_strb = 8'hff;
    desc_axi_o.w_last = 1'b1;
    desc_axi_o.w_user = '0;
    desc_axi_o.w_valid = (state_q == ST_COMP_W);
    desc_axi_o.b_ready = (state_q == ST_COMP_B);
    desc_axi_o.ar_id = '0;
    desc_axi_o.ar_addr = current_desc_addr_q;
    desc_axi_o.ar_len = 8'd3;
    desc_axi_o.ar_size = 3'd3;
    desc_axi_o.ar_burst = 2'b01;
    desc_axi_o.ar_lock = 1'b0;
    desc_axi_o.ar_cache = 4'b0011;
    desc_axi_o.ar_prot = 3'b010;
    desc_axi_o.ar_qos = '0;
    desc_axi_o.ar_region = '0;
    desc_axi_o.ar_user = '0;
    desc_axi_o.ar_valid = (state_q == ST_FETCH_AR);
    desc_axi_o.r_ready = (state_q == ST_FETCH_R);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      current_is_tx_q <= 1'b0;
      current_desc_addr_q <= '0;
      desc_word0_q <= '0;
      desc_word1_q <= '0;
      desc_word2_q <= '0;
      desc_word3_q <= '0;
      fetch_count_q <= '0;
      fetch_error_q <= 1'b0;
      current_ioc_q <= 1'b0;
      current_buffer_addr_q <= '0;
      current_len_q <= '0;
      tx_active_desc_addr_q <= '0;
      tx_active_len_q <= '0;
      tx_active_ioc_q <= 1'b0;
      tx_active_q <= 1'b0;
      tx_completion_pending_q <= 1'b0;
      tx_completion_error_q <= 1'b0;
      rx_active_desc_addr_q <= '0;
      rx_active_ioc_q <= 1'b0;
      rx_active_q <= 1'b0;
      rx_completion_pending_q <= 1'b0;
      rx_completion_len_q <= '0;
      rx_completion_error_q <= 1'b0;
      tx_wait_owner_q <= 1'b0;
      rx_wait_owner_q <= 1'b0;
      tx_head_o <= '0;
      rx_head_o <= '0;
      completion_is_tx_q <= 1'b0;
      completion_ioc_q <= 1'b0;
      completion_len_q <= '0;
      completion_error_q <= '0;
      tx_done_o <= 1'b0;
      tx_error_o <= 1'b0;
      rx_done_o <= 1'b0;
      rx_error_o <= 1'b0;
    end else if (ring_reset_i) begin
      state_q <= ST_IDLE;
      current_is_tx_q <= 1'b0;
      current_desc_addr_q <= '0;
      fetch_count_q <= '0;
      fetch_error_q <= 1'b0;
      tx_active_q <= 1'b0;
      tx_completion_pending_q <= 1'b0;
      rx_active_q <= 1'b0;
      rx_completion_pending_q <= 1'b0;
      tx_wait_owner_q <= 1'b0;
      rx_wait_owner_q <= 1'b0;
      tx_head_o <= '0;
      rx_head_o <= '0;
      tx_done_o <= 1'b0;
      tx_error_o <= 1'b0;
      rx_done_o <= 1'b0;
      rx_error_o <= 1'b0;
    end else begin
      tx_done_o <= 1'b0;
      tx_error_o <= 1'b0;
      rx_done_o <= 1'b0;
      rx_error_o <= 1'b0;

      if (tx_doorbell_i) begin
        tx_wait_owner_q <= 1'b0;
        if (!tx_ring_valid)
          tx_error_o <= 1'b1;
      end
      if (rx_doorbell_i) begin
        rx_wait_owner_q <= 1'b0;
        if (!rx_ring_valid)
          rx_error_o <= 1'b1;
      end
      if (tx_complete_valid_i && tx_active_q) begin
        tx_completion_pending_q <= 1'b1;
        tx_completion_error_q <= tx_complete_error_i;
      end
      if (rx_complete_valid_i && rx_active_q) begin
        rx_completion_pending_q <= 1'b1;
        rx_completion_len_q <= rx_complete_len_i;
        rx_completion_error_q <= rx_complete_error_i;
      end

      unique case (state_q)
        ST_IDLE: begin
          if (tx_completion_pending_q) begin
            tx_active_q <= 1'b0;
            tx_completion_pending_q <= 1'b0;
            current_desc_addr_q <= tx_active_desc_addr_q;
            completion_is_tx_q <= 1'b1;
            completion_ioc_q <= tx_active_ioc_q;
            completion_len_q <= tx_active_len_q;
            completion_error_q <= tx_completion_error_q ? DESC_ERR_PAYLOAD : 8'b0;
            state_q <= ST_COMP_AW;
          end else if (rx_completion_pending_q) begin
            rx_active_q <= 1'b0;
            rx_completion_pending_q <= 1'b0;
            current_desc_addr_q <= rx_active_desc_addr_q;
            completion_is_tx_q <= 1'b0;
            completion_ioc_q <= rx_active_ioc_q;
            completion_len_q <= rx_completion_len_q;
            completion_error_q <= rx_completion_error_q ? DESC_ERR_PAYLOAD : 8'b0;
            state_q <= ST_COMP_AW;
          end else if (tx_enable_i && !tx_active_q && !tx_wait_owner_q &&
                       tx_ring_valid && (tx_head_o != tx_tail_i)) begin
            current_is_tx_q <= 1'b1;
            current_desc_addr_q <= ring_desc_addr(tx_ring_base_i, tx_head_o);
            fetch_count_q <= '0;
            fetch_error_q <= 1'b0;
            state_q <= ST_FETCH_AR;
          end else if (rx_enable_i && !rx_active_q && !rx_wait_owner_q &&
                       rx_ring_valid && (rx_head_o != rx_tail_i)) begin
            current_is_tx_q <= 1'b0;
            current_desc_addr_q <= ring_desc_addr(rx_ring_base_i, rx_head_o);
            fetch_count_q <= '0;
            fetch_error_q <= 1'b0;
            state_q <= ST_FETCH_AR;
          end
        end

        ST_FETCH_AR: begin
          if (desc_axi_o.ar_ready)
            state_q <= ST_FETCH_R;
        end

        ST_FETCH_R: begin
          if (desc_axi_o.r_valid) begin
            unique case (fetch_count_q)
              2'd0: desc_word0_q <= desc_axi_o.r_data;
              2'd1: desc_word1_q <= desc_axi_o.r_data;
              2'd2: desc_word2_q <= desc_axi_o.r_data;
              default: desc_word3_q <= desc_axi_o.r_data;
            endcase
            if (desc_axi_o.r_resp != 2'b00)
              fetch_error_q <= 1'b1;
            if (desc_axi_o.r_last || (fetch_count_q == 2'd3)) begin
              if ((fetch_count_q != 2'd3) || !desc_axi_o.r_last)
                fetch_error_q <= 1'b1;
              state_q <= ST_PARSE;
            end else begin
              fetch_count_q <= fetch_count_q + 2'd1;
            end
          end
        end

        ST_PARSE: begin
          current_ioc_q <= desc_ioc;
          current_buffer_addr_q <= desc_word0_q[47:0];
          current_len_q <= desc_word1_q[15:0];
          if (!desc_own) begin
            if (current_is_tx_q)
              tx_wait_owner_q <= 1'b1;
            else
              rx_wait_owner_q <= 1'b1;
            state_q <= ST_IDLE;
          end else if (fetch_error_q || !desc_format_valid) begin
            completion_is_tx_q <= current_is_tx_q;
            completion_ioc_q <= desc_ioc;
            completion_len_q <= '0;
            completion_error_q <= fetch_error_q ? DESC_ERR_AXI : DESC_ERR_FORMAT;
            state_q <= ST_COMP_AW;
          end else if (current_is_tx_q) begin
            state_q <= ST_TX_LAUNCH;
          end else begin
            state_q <= ST_RX_ARM;
          end
        end

        ST_TX_LAUNCH: begin
          if (tx_launch_ready_i) begin
            tx_active_q <= 1'b1;
            tx_active_desc_addr_q <= current_desc_addr_q;
            tx_active_len_q <= current_len_q;
            tx_active_ioc_q <= current_ioc_q;
            state_q <= ST_IDLE;
          end
        end

        ST_RX_ARM: begin
          if (rx_arm_ready_i) begin
            rx_active_q <= 1'b1;
            rx_active_desc_addr_q <= current_desc_addr_q;
            rx_active_ioc_q <= current_ioc_q;
            state_q <= ST_IDLE;
          end
        end

        ST_COMP_AW: begin
          if (desc_axi_o.aw_ready)
            state_q <= ST_COMP_W;
        end

        ST_COMP_W: begin
          if (desc_axi_o.w_ready)
            state_q <= ST_COMP_B;
        end

        ST_COMP_B: begin
          if (desc_axi_o.b_valid) begin
            if (completion_is_tx_q) begin
              tx_head_o <= ring_next(tx_head_o, tx_ring_count_i);
              if ((desc_axi_o.b_resp != 2'b00) || (completion_error_q != 8'b0))
                tx_error_o <= 1'b1;
              else if (completion_ioc_q)
                tx_done_o <= 1'b1;
            end else begin
              rx_head_o <= ring_next(rx_head_o, rx_ring_count_i);
              if ((desc_axi_o.b_resp != 2'b00) || (completion_error_q != 8'b0))
                rx_error_o <= 1'b1;
              else if (completion_ioc_q)
                rx_done_o <= 1'b1;
            end
            state_q <= ST_IDLE;
          end
        end

        default: state_q <= ST_IDLE;
      endcase

      if (!rx_enable_i &&
          (state_q == ST_IDLE || (!current_is_tx_q &&
           (state_q == ST_FETCH_AR || state_q == ST_FETCH_R ||
            state_q == ST_PARSE || state_q == ST_RX_ARM)))) begin
        rx_active_q <= 1'b0;
        rx_completion_pending_q <= 1'b0;
        rx_wait_owner_q <= 1'b0;
        state_q <= ST_IDLE;
      end
    end
  end

endmodule
