// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Event-driven PLIC source model for eRISCV-MCU SoC tests.
// Software configuration writes arm a scenario; claim/complete bus traffic
// advances it. No scenario progression depends on core execution cycles.
module tb_plic_agent #(
  parameter int unsigned EXT_IRQ_COUNT = 16,
  parameter int unsigned EXT_IRQ_FIRST_SOURCE_ID = 17
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        active_i,
  input  logic        single_irq_i,
  input  logic        source_sweep_i,
  input  logic        priority_i,
  input  logic        irq_ready_i,
  input  logic        dbus_req_i,
  input  logic        dbus_we_i,
  input  logic [31:0] dbus_addr_i,
  input  logic [31:0] dbus_wdata_i,
  input  logic        dbus_write_accept_i,
  input  logic        dbus_resp_valid_i,
  output logic [EXT_IRQ_COUNT-1:0] ext_irq_o,
  output logic        done_o
);

  localparam logic [31:0] PLIC_BASE      = 32'h0c00_0000;
  localparam logic [31:0] ENABLE_ADDR    = PLIC_BASE + 32'h0000_2000;
  localparam logic [31:0] THRESHOLD_ADDR = PLIC_BASE + 32'h0020_0000;
  localparam logic [31:0] CLAIM_ADDR     = PLIC_BASE + 32'h0020_0004;
  localparam int unsigned EXT_IRQ_LAST_SOURCE_ID =
      EXT_IRQ_FIRST_SOURCE_ID + EXT_IRQ_COUNT - 1;

  typedef enum logic [3:0] {
    IDLE,
    SINGLE_ASSERT,
    SINGLE_COMPLETE,
    SWEEP_ASSERT,
    SWEEP_COMPLETE,
    PRIORITY_FIRST_ASSERT,
    PRIORITY_FIRST_COMPLETE,
    PRIORITY_SECOND_CLAIM,
    PRIORITY_SECOND_COMPLETE,
    PRIORITY_THIRD_ASSERT,
    PRIORITY_THIRD_COMPLETE,
    PRIORITY_FOURTH_CLAIM,
    PRIORITY_FOURTH_COMPLETE,
    DONE
  } state_t;

  state_t state_q;
  int unsigned sweep_id_q;
  logic        dbus_txn_valid_q;
  logic        dbus_txn_we_q;
  logic [31:0] dbus_txn_addr_q;
  logic [31:0] dbus_txn_wdata_q;
  logic        dbus_write_accepted;
  bit          trace_enabled;

  initial trace_enabled = $test$plusargs("tb_plic_agent_trace");

  // PLIC writes complete in the request cycle; claim reads retain their
  // registered response path below.
  assign dbus_write_accepted = dbus_req_i && dbus_we_i && dbus_write_accept_i;

  function automatic logic [EXT_IRQ_COUNT-1:0] source_mask(input int unsigned source_id);
    source_mask = '0;
    if ((source_id >= EXT_IRQ_FIRST_SOURCE_ID) &&
        (source_id <= EXT_IRQ_LAST_SOURCE_ID))
      source_mask[source_id - EXT_IRQ_FIRST_SOURCE_ID] = 1'b1;
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q      <= IDLE;
      sweep_id_q   <= EXT_IRQ_FIRST_SOURCE_ID;
      dbus_txn_valid_q <= 1'b0;
      dbus_txn_we_q <= 1'b0;
      dbus_txn_addr_q <= '0;
      dbus_txn_wdata_q <= '0;
      ext_irq_o    <= '0;
      done_o       <= 1'b0;
    end else if (!active_i) begin
      state_q      <= IDLE;
      sweep_id_q   <= EXT_IRQ_FIRST_SOURCE_ID;
      dbus_txn_valid_q <= 1'b0;
      dbus_txn_we_q <= 1'b0;
      dbus_txn_addr_q <= '0;
      dbus_txn_wdata_q <= '0;
      ext_irq_o    <= '0;
      done_o       <= 1'b0;
    end else begin
      if (dbus_req_i) begin
        dbus_txn_valid_q <= 1'b1;
        dbus_txn_we_q <= dbus_we_i;
        dbus_txn_addr_q <= dbus_addr_i;
        dbus_txn_wdata_q <= dbus_wdata_i;
      end else if (dbus_resp_valid_i) begin
        dbus_txn_valid_q <= 1'b0;
      end
      unique case (state_q)
        IDLE: begin
          ext_irq_o <= '0;
          if (single_irq_i && dbus_write_accepted && (dbus_addr_i == ENABLE_ADDR) &&
              dbus_wdata_i[EXT_IRQ_FIRST_SOURCE_ID]) begin
            if (trace_enabled)
              $display("TB PLIC AGENT: source %0d armed by enable write",
                       EXT_IRQ_FIRST_SOURCE_ID);
            state_q <= SINGLE_ASSERT;
          end else if ((source_sweep_i || priority_i) && dbus_write_accepted &&
                       (dbus_addr_i == THRESHOLD_ADDR) && (dbus_wdata_i == 32'h0)) begin
            if (trace_enabled)
              $display("TB PLIC AGENT: %s armed by threshold write",
                       source_sweep_i ? "source sweep" : "priority scenario");
            state_q <= source_sweep_i ? SWEEP_ASSERT : PRIORITY_FIRST_ASSERT;
          end
        end

        SINGLE_ASSERT: begin
          if (irq_ready_i) ext_irq_o <= source_mask(EXT_IRQ_FIRST_SOURCE_ID);
          if (dbus_resp_valid_i && dbus_txn_valid_q &&
              !dbus_txn_we_q && (dbus_txn_addr_q == CLAIM_ADDR)) begin
            if (trace_enabled)
              $display("TB PLIC AGENT: source %0d claim observed",
                       EXT_IRQ_FIRST_SOURCE_ID);
            ext_irq_o <= '0;
            state_q <= SINGLE_COMPLETE;
          end
        end
        SINGLE_COMPLETE: begin
          if (dbus_write_accepted && (dbus_addr_i == CLAIM_ADDR)) begin
            if (trace_enabled)
              $display("TB PLIC AGENT: source %0d complete observed",
                       EXT_IRQ_FIRST_SOURCE_ID);
            state_q <= DONE;
            done_o <= 1'b1;
          end
        end

        SWEEP_ASSERT: begin
          if (irq_ready_i) ext_irq_o <= source_mask(sweep_id_q);
          if (dbus_resp_valid_i && dbus_txn_valid_q &&
              !dbus_txn_we_q && (dbus_txn_addr_q == CLAIM_ADDR)) begin
            if (trace_enabled)
              $display("TB PLIC AGENT: source %0d claim observed", sweep_id_q);
            ext_irq_o <= '0;
            state_q <= SWEEP_COMPLETE;
          end
        end
        SWEEP_COMPLETE: begin
          if (dbus_write_accepted && (dbus_addr_i == CLAIM_ADDR) &&
              (dbus_wdata_i[5:0] == sweep_id_q[5:0])) begin
            if (trace_enabled)
              $display("TB PLIC AGENT: source %0d complete observed", sweep_id_q);
            if (sweep_id_q == EXT_IRQ_LAST_SOURCE_ID) begin
              state_q <= DONE;
              done_o <= 1'b1;
            end else begin
              sweep_id_q <= sweep_id_q + 1'b1;
              state_q <= SWEEP_ASSERT;
            end
          end
        end

        PRIORITY_FIRST_ASSERT: begin
          if (irq_ready_i)
            ext_irq_o <= source_mask(EXT_IRQ_FIRST_SOURCE_ID) |
                         source_mask(EXT_IRQ_FIRST_SOURCE_ID + 4);
          if (dbus_resp_valid_i && dbus_txn_valid_q &&
              !dbus_txn_we_q && (dbus_txn_addr_q == CLAIM_ADDR)) begin
            ext_irq_o <= '0;
            state_q <= PRIORITY_FIRST_COMPLETE;
          end
        end
        PRIORITY_FIRST_COMPLETE: begin
          if (dbus_write_accepted && (dbus_addr_i == CLAIM_ADDR))
            state_q <= PRIORITY_SECOND_CLAIM;
        end
        PRIORITY_SECOND_CLAIM: begin
          if (dbus_resp_valid_i && dbus_txn_valid_q && !dbus_txn_we_q &&
              (dbus_txn_addr_q == CLAIM_ADDR))
            state_q <= PRIORITY_SECOND_COMPLETE;
        end
        PRIORITY_SECOND_COMPLETE: begin
          if (dbus_write_accepted && (dbus_addr_i == CLAIM_ADDR))
            state_q <= PRIORITY_THIRD_ASSERT;
        end
        PRIORITY_THIRD_ASSERT: begin
          if (irq_ready_i)
            ext_irq_o <= source_mask(EXT_IRQ_FIRST_SOURCE_ID + 1) |
                         source_mask(EXT_IRQ_FIRST_SOURCE_ID + 2);
          if (dbus_resp_valid_i && dbus_txn_valid_q &&
              !dbus_txn_we_q && (dbus_txn_addr_q == CLAIM_ADDR)) begin
            ext_irq_o <= '0;
            state_q <= PRIORITY_THIRD_COMPLETE;
          end
        end
        PRIORITY_THIRD_COMPLETE: begin
          if (dbus_write_accepted && (dbus_addr_i == CLAIM_ADDR))
            state_q <= PRIORITY_FOURTH_CLAIM;
        end
        PRIORITY_FOURTH_CLAIM: begin
          if (dbus_resp_valid_i && dbus_txn_valid_q && !dbus_txn_we_q &&
              (dbus_txn_addr_q == CLAIM_ADDR))
            state_q <= PRIORITY_FOURTH_COMPLETE;
        end
        PRIORITY_FOURTH_COMPLETE: begin
          if (dbus_write_accepted && (dbus_addr_i == CLAIM_ADDR)) begin
            state_q <= DONE;
            done_o <= 1'b1;
          end
        end

        default: begin
          ext_irq_o <= '0;
          done_o <= 1'b1;
        end
      endcase
    end
  end
endmodule
