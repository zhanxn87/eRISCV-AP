// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Boot subsystem for instruction-memory loading before normal fetch is released.
// The selected boot source produces a common command stream consumed by
// imem_boot_ctrl; inactive sources are gated by boot_mode_i so future boot
// transports can be added without changing the SoC top-level memory path.
module boot_subsystem #(
  parameter int DMI_ADDR_WIDTH = 7,
  parameter int IMEM_BOOT_ADDR_WIDTH = 13
) (
  // Clock/reset and boot-mode selection
  input  logic                      clk,
  input  logic                      rst_n,
  input  logic [2:0]                boot_mode_i,

  // DMI boot transport
  input  logic                      dmi_req_valid_i,
  input  logic [DMI_ADDR_WIDTH-1:0] dmi_req_addr_i,
  input  logic [31:0]               dmi_req_wdata_i,
  input  logic [1:0]                dmi_req_op_i,
  output logic                      dmi_req_selected_o,
  output logic                      dmi_resp_valid_o,
  output logic [31:0]               dmi_resp_rdata_o,
  output logic [1:0]                dmi_resp_op_o,

  // UART boot transport and diagnostics
  input  logic                      boot_uart_rx_i,
  input  logic [31:0]               boot_uart_divisor_i,
  output logic                      boot_uart_overrun_o,
  output logic                      boot_uart_protocol_error_o,

  // IMEM boot-write port and fetch release
  output logic                      imem_boot_we_o,
  output logic [IMEM_BOOT_ADDR_WIDTH-1:0] imem_boot_addr_o,
  output logic [31:0]               imem_boot_wdata_o,
  output logic [3:0]                imem_boot_be_o,
  output logic                      boot_fetch_enable_o
);

  localparam logic [2:0] BOOT_MODE_BYPASS    = 3'd0;
  localparam logic [2:0] BOOT_MODE_JTAG_DMI  = 3'd1;
  localparam logic [2:0] BOOT_MODE_UART      = 3'd2;
  // Reserved for a future SPI flash boot reader.  The former SPI-slave
  // download protocol is intentionally not part of the product interface.
  localparam logic [2:0] BOOT_MODE_SPI_FLASH = 3'd3;

  // Boot-mode enables and UART byte stream
  logic        dmi_boot_enable;
  logic        uart_boot_enable;
  logic        dmi_boot_selected;
  logic        boot_uart_byte_valid;
  logic [7:0]  boot_uart_byte;
  // DMI boot command source
  logic        dmi_boot_cmd_valid;
  logic        dmi_boot_cmd_set_addr;
  logic        dmi_boot_cmd_write;
  logic        dmi_boot_cmd_hold_fetch;
  logic        dmi_boot_cmd_release_fetch;
  logic        dmi_boot_cmd_auto_inc_we;
  logic        dmi_boot_cmd_auto_inc;
  logic [IMEM_BOOT_ADDR_WIDTH-1:0] dmi_boot_cmd_addr;
  logic [31:0] dmi_boot_cmd_wdata;
  logic [3:0]  dmi_boot_cmd_be;
  // UART boot command source
  logic        uart_boot_cmd_valid;
  logic        uart_boot_cmd_set_addr;
  logic        uart_boot_cmd_write;
  logic        uart_boot_cmd_hold_fetch;
  logic        uart_boot_cmd_release_fetch;
  logic        uart_boot_cmd_auto_inc_we;
  logic        uart_boot_cmd_auto_inc;
  logic [IMEM_BOOT_ADDR_WIDTH-1:0] uart_boot_cmd_addr;
  logic [31:0] uart_boot_cmd_wdata;
  logic [3:0]  uart_boot_cmd_be;
  // Selected command and boot-controller state
  logic        boot_cmd_valid;
  logic        boot_cmd_set_addr;
  logic        boot_cmd_write;
  logic        boot_cmd_hold_fetch;
  logic        boot_cmd_release_fetch;
  logic        boot_cmd_auto_inc_we;
  logic        boot_cmd_auto_inc;
  logic [IMEM_BOOT_ADDR_WIDTH-1:0] boot_cmd_addr;
  logic [31:0] boot_cmd_wdata;
  logic [3:0]  boot_cmd_be;
  logic [IMEM_BOOT_ADDR_WIDTH-1:0] boot_current_addr;
  logic        boot_auto_inc;
  logic        boot_fetch_released;


  // Decode the board-selected boot transport. BYPASS leaves the loader idle
  // and allows the core to fetch immediately after reset. UART boot is a
  // one-shot transport: after RELEASE it must relinquish uart_rx_i to the
  // runtime UART, so terminal bytes cannot be decoded as boot opcodes.
  assign dmi_boot_enable = (boot_mode_i == BOOT_MODE_JTAG_DMI);
  assign uart_boot_enable = (boot_mode_i == BOOT_MODE_UART) & !boot_fetch_released;
  assign dmi_req_selected_o = dmi_boot_enable & dmi_boot_selected;
  assign boot_fetch_enable_o = (boot_mode_i == BOOT_MODE_BYPASS) ? 1'b1 : boot_fetch_released;

  dmi_boot_slave #(
    .DMI_ADDR_WIDTH(DMI_ADDR_WIDTH),
    .BOOT_ADDR_WIDTH(IMEM_BOOT_ADDR_WIDTH)
  ) dmi_boot_slave_i (
    // DMI request and response
    .dmi_req_valid_i      (dmi_req_valid_i & dmi_boot_enable),
    .dmi_req_addr_i       (dmi_req_addr_i),
    .dmi_req_wdata_i      (dmi_req_wdata_i),
    .dmi_req_op_i         (dmi_req_op_i),
    .dmi_req_selected_o   (dmi_boot_selected),
    .dmi_resp_valid_o     (dmi_resp_valid_o),
    .dmi_resp_rdata_o     (dmi_resp_rdata_o),
    .dmi_resp_op_o        (dmi_resp_op_o),
    // Current boot-controller state
    .boot_current_addr_i  (boot_current_addr),
    .boot_auto_inc_i      (boot_auto_inc),
    .boot_fetch_released_i(boot_fetch_released),
    // DMI command source
    .boot_cmd_valid_o     (dmi_boot_cmd_valid),
    .boot_cmd_set_addr_o  (dmi_boot_cmd_set_addr),
    .boot_cmd_write_o     (dmi_boot_cmd_write),
    .boot_cmd_hold_fetch_o(dmi_boot_cmd_hold_fetch),
    .boot_cmd_release_fetch_o(dmi_boot_cmd_release_fetch),
    .boot_cmd_auto_inc_we_o(dmi_boot_cmd_auto_inc_we),
    .boot_cmd_auto_inc_o  (dmi_boot_cmd_auto_inc),
    .boot_cmd_addr_o      (dmi_boot_cmd_addr),
    .boot_cmd_wdata_o     (dmi_boot_cmd_wdata),
    .boot_cmd_be_o        (dmi_boot_cmd_be)
  );

  boot_uart_rx boot_uart_rx_inst (
    // Clock/reset and enabled UART receiver
    .clk         (clk),
    .rst_n       (rst_n),
    .enable_i    (uart_boot_enable),
    .rx_i        (boot_uart_rx_i),
    .divisor_i   (boot_uart_divisor_i),
    .byte_valid_o(boot_uart_byte_valid),
    .byte_o      (boot_uart_byte),
    .overrun_o   (boot_uart_overrun_o)
  );

  uart_boot_slave #(
    .BOOT_ADDR_WIDTH(IMEM_BOOT_ADDR_WIDTH)
  ) uart_boot_slave_i (
    // Clock/reset and UART byte stream
    .clk                     (clk),
    .rst_n                   (rst_n),
    .uart_boot_valid_i       (boot_uart_byte_valid & uart_boot_enable),
    .uart_boot_data_i        (boot_uart_byte),
    .uart_boot_ready_o       (),
    .protocol_error_o        (boot_uart_protocol_error_o),
    // UART command source
    .boot_cmd_valid_o        (uart_boot_cmd_valid),
    .boot_cmd_set_addr_o     (uart_boot_cmd_set_addr),
    .boot_cmd_write_o        (uart_boot_cmd_write),
    .boot_cmd_hold_fetch_o   (uart_boot_cmd_hold_fetch),
    .boot_cmd_release_fetch_o(uart_boot_cmd_release_fetch),
    .boot_cmd_auto_inc_we_o  (uart_boot_cmd_auto_inc_we),
    .boot_cmd_auto_inc_o     (uart_boot_cmd_auto_inc),
    .boot_cmd_addr_o         (uart_boot_cmd_addr),
    .boot_cmd_wdata_o        (uart_boot_cmd_wdata),
    .boot_cmd_be_o           (uart_boot_cmd_be)
  );

  // All boot transports use the same command shape; this arbiter provides the
  // single writer seen by the instruction-memory boot controller.
  boot_source_arbiter #(
    .BOOT_ADDR_WIDTH(IMEM_BOOT_ADDR_WIDTH)
  ) boot_source_arbiter_i (
    // DMI command source (highest priority)
    .src0_valid_i        (dmi_boot_cmd_valid & dmi_boot_enable),
    .src0_set_addr_i     (dmi_boot_cmd_set_addr),
    .src0_write_i        (dmi_boot_cmd_write),
    .src0_hold_fetch_i   (dmi_boot_cmd_hold_fetch),
    .src0_release_fetch_i(dmi_boot_cmd_release_fetch),
    .src0_auto_inc_we_i  (dmi_boot_cmd_auto_inc_we),
    .src0_auto_inc_i     (dmi_boot_cmd_auto_inc),
    .src0_addr_i         (dmi_boot_cmd_addr),
    .src0_wdata_i        (dmi_boot_cmd_wdata),
    .src0_be_i           (dmi_boot_cmd_be),
    // UART command source
    .src1_valid_i        (uart_boot_cmd_valid & uart_boot_enable),
    .src1_set_addr_i     (uart_boot_cmd_set_addr),
    .src1_write_i        (uart_boot_cmd_write),
    .src1_hold_fetch_i   (uart_boot_cmd_hold_fetch),
    .src1_release_fetch_i(uart_boot_cmd_release_fetch),
    .src1_auto_inc_we_i  (uart_boot_cmd_auto_inc_we),
    .src1_auto_inc_i     (uart_boot_cmd_auto_inc),
    .src1_addr_i         (uart_boot_cmd_addr),
    .src1_wdata_i        (uart_boot_cmd_wdata),
    .src1_be_i           (uart_boot_cmd_be),
    // Reserved source 2 (future SPI flash boot reader)
    .src2_valid_i        (1'b0),
    .src2_set_addr_i     (1'b0),
    .src2_write_i        (1'b0),
    .src2_hold_fetch_i   (1'b0),
    .src2_release_fetch_i(1'b0),
    .src2_auto_inc_we_i  (1'b0),
    .src2_auto_inc_i     (1'b0),
    .src2_addr_i         ('0),
    .src2_wdata_i        (32'h0000_0000),
    .src2_be_i           (4'h0),
    // Selected command to the boot controller
    .cmd_valid_o         (boot_cmd_valid),
    .cmd_set_addr_o      (boot_cmd_set_addr),
    .cmd_write_o         (boot_cmd_write),
    .cmd_hold_fetch_o    (boot_cmd_hold_fetch),
    .cmd_release_fetch_o (boot_cmd_release_fetch),
    .cmd_auto_inc_we_o   (boot_cmd_auto_inc_we),
    .cmd_auto_inc_o      (boot_cmd_auto_inc),
    .cmd_addr_o          (boot_cmd_addr),
    .cmd_wdata_o         (boot_cmd_wdata),
    .cmd_be_o            (boot_cmd_be)
  );

  imem_boot_ctrl #(
    .IMEM_BOOT_ADDR_WIDTH(IMEM_BOOT_ADDR_WIDTH)
  ) imem_boot_ctrl_i (
    // Clock/reset and selected boot command
    .clk                 (clk),
    .rst_n               (rst_n),
    .cmd_valid_i         (boot_cmd_valid),
    .cmd_set_addr_i      (boot_cmd_set_addr),
    .cmd_write_i         (boot_cmd_write),
    .cmd_hold_fetch_i    (boot_cmd_hold_fetch),
    .cmd_release_fetch_i (boot_cmd_release_fetch),
    .cmd_auto_inc_we_i   (boot_cmd_auto_inc_we),
    .cmd_auto_inc_i      (boot_cmd_auto_inc),
    .cmd_addr_i          (boot_cmd_addr),
    .cmd_wdata_i         (boot_cmd_wdata),
    .cmd_be_i            (boot_cmd_be),
    // Boot-controller state feedback
    .current_addr_o      (boot_current_addr),
    .auto_inc_o          (boot_auto_inc),
    .fetch_released_o    (boot_fetch_released),
    // IMEM boot-write port
    .imem_boot_we_o      (imem_boot_we_o),
    .imem_boot_addr_o    (imem_boot_addr_o),
    .imem_boot_wdata_o   (imem_boot_wdata_o),
    .imem_boot_be_o      (imem_boot_be_o)
  );

endmodule
