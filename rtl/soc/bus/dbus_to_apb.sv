// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// DBus to APB bridge: converts simple dbus requests to AMBA APB protocol.
// Uses a 3-state FSM (IDLE/SETUP/ACCESS) and a request queue to handle
// backpressure when APB transactions are in progress.
module dbus_to_apb (
  input  logic        clk,
  input  logic        rst_n,

  // DBus interface
  input  logic        dbus_req_i,
  input  logic        dbus_we_i,
  input  logic [3:0]  dbus_be_i,
  input  logic [31:0] dbus_addr_i,
  input  logic [31:0] dbus_wdata_i,
  output logic        dbus_resp_valid_o,
  output logic [31:0] dbus_rdata_o,
  output logic        dbus_err_o,

  // APB interface
  output logic        psel_o,
  output logic        penable_o,
  output logic        pwrite_o,
  output logic [31:0] paddr_o,
  output logic [31:0] pwdata_o,
  output logic [3:0]  pstrb_o,
  input  logic        pready_i,
  input  logic [31:0] prdata_i,
  input  logic        pslverr_i
);

  // APB state machine: 3-state FSM for APB protocol timing
  // APB transfer state
  typedef enum logic [1:0] {
    APB_IDLE,    // No transaction in progress
    APB_SETUP,   // Setup phase: assert psel, drive address/control
    APB_ACCESS   // Access phase: assert penable, wait for pready
  } apb_state_t;

  // State machine registers
  apb_state_t state_q;
  // Outstanding APB read and queued DBus request
  logic       pending_read_q;

  // Request queue for handling backpressure
  logic       queued_valid_q;
  logic       queued_we_q;
  logic [3:0] queued_be_q;
  logic [31:0] queued_addr_q;
  logic [31:0] queued_wdata_q;

  // Mux selection: use queued request if valid, otherwise use incoming request
  // Request selected for the next APB setup phase
  logic       next_we;
  logic [3:0] next_be;
  logic [31:0] next_addr;
  logic [31:0] next_wdata;
  logic       start_from_queue;

  assign start_from_queue = queued_valid_q;
  // Select request source: queued or incoming
  assign next_we          = start_from_queue ? queued_we_q    : dbus_we_i;
  assign next_be          = start_from_queue ? queued_be_q    : dbus_be_i;
  assign next_addr        = start_from_queue ? queued_addr_q  : dbus_addr_i;
  assign next_wdata       = start_from_queue ? queued_wdata_q : dbus_wdata_i;

  // APB state machine and request queue logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q        <= APB_IDLE;
      pending_read_q <= 1'b0;
      queued_valid_q <= 1'b0;
      queued_we_q    <= 1'b0;
      queued_be_q    <= 4'b0000;
      queued_addr_q  <= 32'h0000_0000;
      queued_wdata_q <= 32'h0000_0000;
      psel_o         <= 1'b0;
      penable_o      <= 1'b0;
      pwrite_o       <= 1'b0;
      paddr_o        <= 32'h0000_0000;
      pwdata_o       <= 32'h0000_0000;
      pstrb_o        <= 4'b0000;
      dbus_resp_valid_o <= 1'b0;
      dbus_rdata_o   <= 32'h0000_0000;
      dbus_err_o     <= 1'b0;
    end else begin
      // Default: clear response signals
      dbus_resp_valid_o <= 1'b0;
      dbus_err_o <= 1'b0;

      // Queue incoming request if busy and queue is empty
      if (dbus_req_i && (state_q != APB_IDLE) && !queued_valid_q) begin
        queued_valid_q <= 1'b1;
        queued_we_q    <= dbus_we_i;
        queued_be_q    <= dbus_be_i;
        queued_addr_q  <= dbus_addr_i;
        queued_wdata_q <= dbus_wdata_i;
      end

      unique case (state_q)
        APB_IDLE: begin
          psel_o    <= 1'b0;
          penable_o <= 1'b0;

          // Start new transaction if queued or incoming request
          if (queued_valid_q || dbus_req_i) begin
            psel_o         <= 1'b1;
            penable_o      <= 1'b0;
            pwrite_o       <= next_we;
            paddr_o        <= next_addr;
            pwdata_o       <= next_wdata;
            pstrb_o        <= next_we ? next_be : 4'b0000;
            pending_read_q <= !next_we;
            state_q        <= APB_SETUP;
            // Handle queue management when starting from queue
            if (queued_valid_q) begin
              if (dbus_req_i) begin
                // New request arrived, keep queue valid
                queued_valid_q <= 1'b1;
                queued_we_q    <= dbus_we_i;
                queued_be_q    <= dbus_be_i;
                queued_addr_q  <= dbus_addr_i;
                queued_wdata_q <= dbus_wdata_i;
              end else begin
                // No new request, clear queue
                queued_valid_q <= 1'b0;
              end
            end
          end
        end

        APB_SETUP: begin
          // Assert penable to start access phase
          psel_o    <= 1'b1;
          penable_o <= 1'b1;
          state_q   <= APB_ACCESS;
        end

        APB_ACCESS: begin
          // Wait for peripheral to assert pready
          if (pready_i) begin
            // Transaction complete: return response
            dbus_resp_valid_o <= 1'b1;
            dbus_rdata_o      <= pending_read_q ? prdata_i : 32'h0000_0000;
            dbus_err_o        <= pslverr_i;
            psel_o         <= 1'b0;
            penable_o      <= 1'b0;
            pending_read_q <= 1'b0;

            // Start next transaction if queued
            if (queued_valid_q) begin
              psel_o         <= 1'b1;
              penable_o      <= 1'b0;
              pwrite_o       <= queued_we_q;
              paddr_o        <= queued_addr_q;
              pwdata_o       <= queued_wdata_q;
              pstrb_o        <= queued_we_q ? queued_be_q : 4'b0000;
              pending_read_q <= !queued_we_q;
              state_q        <= APB_SETUP;

              // Update queue with any new incoming request
              if (dbus_req_i) begin
                queued_valid_q <= 1'b1;
                queued_we_q    <= dbus_we_i;
                queued_be_q    <= dbus_be_i;
                queued_addr_q  <= dbus_addr_i;
                queued_wdata_q <= dbus_wdata_i;
              end else begin
                queued_valid_q <= 1'b0;
              end
            end else begin
              // No queued request, return to idle
              state_q <= APB_IDLE;
            end
          end
        end

        default: begin
          state_q <= APB_IDLE;
        end
      endcase
    end
  end

endmodule
