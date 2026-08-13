// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Dedicated UART receiver for boot loading.
// This wrapper keeps boot UART wiring separate from the APB UART while reusing
// the same synthesizable UART RX implementation.
module boot_uart_rx (
  // Clock and reset
  input  logic        clk,
  input  logic        rst_n,

  // UART RX sampling configuration
  input  logic        enable_i,
  input  logic        rx_i,
  input  logic [31:0] divisor_i,

  // Decoded byte and overflow indication
  output logic        byte_valid_o,
  output logic [7:0]  byte_o,
  output logic        overrun_o
);

  uart_rx uart_rx_i (
    .clk        (clk),
    .rst_n      (rst_n),
    .rx_i       (rx_i),
    .rx_enable_i(enable_i),
    .divisor_i  (divisor_i),
    .valid_o    (byte_valid_o),
    .data_o     (byte_o)
  );

  // The boot protocol consumes each received byte in its valid cycle.
  assign overrun_o = 1'b0;

endmodule
