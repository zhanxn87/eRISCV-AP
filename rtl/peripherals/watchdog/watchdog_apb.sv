// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Watchdog Timer — APB peripheral
// Counts down from TIMEOUT; FEED resets counter. WINDOW mode enforces minimal
// feed interval. LOCK prevents reconfiguration until reset. Debug-freeze
// pauses counter. PRETIMEOUT provides an early-warning IRQ before final reset.
// Reset-cause recorded in STATUS.
// Style: follows timer_apb.sv conventions (pready_o=1, pslverr on bad offset).

module watchdog_apb #(
  parameter int unsigned WDT_COUNTER_WIDTH = 32
) (
  input  logic        pclk,
  input  logic        presetn,
  input  logic        psel_i,
  input  logic        penable_i,
  input  logic        pwrite_i,
  input  logic [31:0] paddr_i,
  input  logic [31:0] pwdata_i,
  input  logic [3:0]  pstrb_i,
  output logic        pready_o,
  output logic [31:0] prdata_o,
  output logic        pslverr_o,

  input  logic        debug_halted_i,   // from debug module: 1 = core halted, freeze counter
  output logic        irq_o,            // sticky pre-timeout warning interrupt
  output logic        enabled_o,        // clock-controller safety override
  output logic        locked_o,         // clock/reset-controller safety override
  output logic        wdt_rst_n_o       // system reset (active low)
);

  // ── Register offsets (4-byte aligned) ──
  localparam logic [7:0] REG_CTRL    = 8'h00;   // [0] enable, [1] window_en, [2] irq_en
  localparam logic [7:0] REG_TIMEOUT = 8'h04;   // timeout countdown value
  localparam logic [7:0] REG_WINDOW  = 8'h08;   // feed window opens when count <= value; 0 disables
  localparam logic [7:0] REG_FEED    = 8'h0c;   // write 0xACCE55ED to feed
  localparam logic [7:0] REG_STATUS  = 8'h10;   // [0] expired, [1] reset cause, [2] locked, [3] pretimeout
  localparam logic [7:0] REG_LOCK    = 8'h14;   // write 1 to lock; read returns lock state
  localparam logic [7:0] REG_PRETIMEOUT = 8'h18; // remaining cycles for early warning; 0 disables

  localparam logic [31:0] FEED_MAGIC = 32'hACCE55ED;

  // ── Internal signals ──
  logic        apb_access;
  logic [7:0]  reg_offset;

  logic [31:0] ctrl_q;
  logic [31:0] timeout_q;
  logic [31:0] window_q;
  logic [31:0] count_q;
  logic [31:0] pretimeout_q;
  logic        expired_q;
  logic        reset_cause_q;
  logic        locked_q;
  logic        pretimeout_pending_q;
  logic        feed_valid;
  logic        window_ok;
  logic        counter_expired;
  logic        pretimeout_hit;
  logic [31:0] ctrl_wdata;

  function automatic logic [31:0] merge_pstrb(
    input logic [31:0] current_value,
    input logic [31:0] write_value,
    input logic [3:0]  write_strobe
  );
    logic [31:0] merged_value;
    merged_value = current_value;
    for (int byte_index = 0; byte_index < 4; byte_index++) begin
      if (write_strobe[byte_index])
        merged_value[byte_index*8 +: 8] = write_value[byte_index*8 +: 8];
    end
    return merged_value;
  endfunction

  assign apb_access = psel_i & penable_i;
  assign reg_offset = paddr_i[7:0];
  assign pready_o   = 1'b1;
  assign pslverr_o  = apb_access &&
                      (reg_offset != REG_CTRL) &&
                      (reg_offset != REG_TIMEOUT) &&
                      (reg_offset != REG_WINDOW) &&
                      (reg_offset != REG_FEED) &&
                      (reg_offset != REG_STATUS) &&
                      (reg_offset != REG_LOCK) &&
                      (reg_offset != REG_PRETIMEOUT);

  // ── Feed detection ──
  assign feed_valid = apb_access && pwrite_i && !pslverr_o &&
                      (reg_offset == REG_FEED) && (pstrb_i == 4'hf) &&
                      (pwdata_i == FEED_MAGIC);

  // ── Window check: feed only after the countdown reaches the open window ──
  assign window_ok = !ctrl_q[1] ||                           // window mode disabled
                     (window_q == 32'h0000_0000) ||          // window not configured
                     (count_q <= window_q);                  // window is open
  assign ctrl_wdata = merge_pstrb(ctrl_q, pwdata_i, pstrb_i);

  // ── Counter expiry ──
  assign counter_expired = ctrl_q[0] && !debug_halted_i && (count_q == 32'h0000_0000);
  assign pretimeout_hit = ctrl_q[0] && ctrl_q[2] && !debug_halted_i &&
                          (pretimeout_q != 32'h0000_0000) &&
                          (pretimeout_q < timeout_q) &&
                          (count_q > 32'h0000_0000) &&
                          ((count_q - 32'h0000_0001) == pretimeout_q);

  // ── Outputs ──
  assign irq_o       = pretimeout_pending_q && ctrl_q[2];
  assign enabled_o   = ctrl_q[0];
  assign locked_o    = locked_q;
  assign wdt_rst_n_o = counter_expired ? 1'b0 : 1'b1;       // active-low reset

  // ── APB read mux ──
  always_comb begin
    unique case (reg_offset)
      REG_CTRL:    prdata_o = ctrl_q;
      REG_TIMEOUT: prdata_o = timeout_q;
      REG_WINDOW:  prdata_o = window_q;
      REG_FEED:    prdata_o = 32'h0000_0000;                 // write-only
      REG_STATUS:  prdata_o = {28'h0000_000, pretimeout_pending_q,
                               locked_q, reset_cause_q, expired_q};
      REG_LOCK:    prdata_o = {31'h0000_0000, locked_q};
      REG_PRETIMEOUT: prdata_o = pretimeout_q;
      default:     prdata_o = 32'h0000_0000;
    endcase
  end

  // ── Sequential logic ──
  always_ff @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      ctrl_q        <= 32'h0000_0000;
      timeout_q     <= 32'hFFFF_FFFF;           // max timeout after reset
      window_q      <= 32'h0000_0000;
      count_q       <= 32'hFFFF_FFFF;
      pretimeout_q  <= 32'h0000_0000;
      expired_q     <= 1'b0;
      reset_cause_q <= 1'b0;
      locked_q      <= 1'b0;
      pretimeout_pending_q <= 1'b0;
    end else begin

      // ── Counter ──
      if (!ctrl_q[0] || debug_halted_i) begin
        // disabled or debug-frozen: counter holds
      end else if (feed_valid && window_ok) begin
        count_q <= timeout_q;
      end else if (count_q > 32'h0000_0000) begin
        count_q <= count_q - 32'h0000_0001;
      end

      // ── Expiry latch ──
      if (counter_expired) begin
        expired_q     <= 1'b1;
        reset_cause_q <= 1'b1;                 // sticky reset-cause
      end

      if (pretimeout_hit)
        pretimeout_pending_q <= 1'b1;

      // ── APB writes ──
      if (apb_access && pwrite_i && !pslverr_o && !locked_q) begin
        unique case (reg_offset)
          REG_CTRL: begin
            ctrl_q <= ctrl_wdata;
            // Reload counter on enable transition (0→1)
            if (!ctrl_q[0] && ctrl_wdata[0])
              count_q <= timeout_q;
          end
          REG_TIMEOUT: timeout_q <= merge_pstrb(timeout_q, pwdata_i, pstrb_i);
          REG_WINDOW:  window_q  <= merge_pstrb(window_q, pwdata_i, pstrb_i);
          REG_STATUS: begin
            // W1C event flags; reset cause remains sticky until reset.
            if (pstrb_i[0] && pwdata_i[0] && !counter_expired)
              expired_q <= 1'b0;
            if (pstrb_i[0] && pwdata_i[3] && !pretimeout_hit)
              pretimeout_pending_q <= 1'b0;
          end
          REG_PRETIMEOUT: pretimeout_q <= merge_pstrb(pretimeout_q, pwdata_i, pstrb_i);
          default: ;
        endcase
      end

      // A successful feed starts a fresh warning interval. Disabling the WDT
      // also removes a stale level interrupt from the PLIC.
      if ((feed_valid && window_ok) ||
          (apb_access && pwrite_i && !pslverr_o && !locked_q &&
           (reg_offset == REG_CTRL) && !ctrl_wdata[0]))
        pretimeout_pending_q <= 1'b0;

      // ── LOCK register (separate from locked_q gating) ──
      if (apb_access && pwrite_i && !pslverr_o && (reg_offset == REG_LOCK)) begin
        if (!locked_q && pstrb_i[0] && pwdata_i[0])
          locked_q <= 1'b1;
      end

    end
  end

endmodule
