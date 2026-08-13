// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Top-level system-control island for debug and boot.
// The SoC core sees only halt/resume and instruction-memory boot commands; JTAG
// DMI routing and boot-source selection stay contained in this subsystem.
module sys_ctrl #(
  parameter int DMI_ADDR_WIDTH = 7,
  parameter int IMEM_BOOT_ADDR_WIDTH = 13
) (
  // System clock/reset and boot-mode selection
  input  logic        clk,
  input  logic        rst_n,
  input  logic [2:0]  boot_mode_i,

  // JTAG debug pins
  input  logic        jtag_tck_i,
  input  logic        jtag_tms_i,
  input  logic        jtag_tdi_i,
  output logic        jtag_tdo_o,
  input  logic        jtag_trst_n_i,

  // Hart run-state and abstract-register access
  output logic        hart_halt_req_o,
  output logic        hart_resume_req_o,
  input  logic        hart_halted_i,
  input  logic        hart_running_i,
  input  logic [31:0] hart_pc_i,
  input  logic [2:0]  hart_cause_i,

  output logic        debug_reg_req_valid_o,
  output logic        debug_reg_write_o,
  output logic [15:0] debug_reg_addr_o,
  output logic [31:0] debug_reg_wdata_o,
  input  logic [31:0] debug_reg_rdata_i,
  input  logic        debug_reg_error_i,

  // Debug system-bus access transaction
  output logic        sba_req_o,
  output logic        sba_we_o,
  output logic [31:0] sba_addr_o,
  output logic [31:0] sba_wdata_o,
  output logic [3:0]  sba_be_o,
  input  logic        sba_resp_valid_i,
  input  logic [31:0] sba_rdata_i,
  input  logic        sba_err_i,

  // IMEM boot-write port and fetch release
  output logic        imem_boot_we_o,
  output logic [IMEM_BOOT_ADDR_WIDTH-1:0] imem_boot_addr_o,
  output logic [31:0] imem_boot_wdata_o,
  output logic [3:0]  imem_boot_be_o,
  output logic        boot_fetch_enable_o,

  // UART boot pin, configuration, and diagnostics
  input  logic        boot_uart_rx_i,
  input  logic [31:0] boot_uart_divisor_i,
  output logic        boot_uart_overrun_o,
  output logic        boot_uart_protocol_error_o
);

  // DMI transport and response-mux state
  logic                      dm_req_valid;
  logic [DMI_ADDR_WIDTH-1:0] dm_req_addr;
  logic [31:0]               dm_req_wdata;
  logic [1:0]                dm_req_op;
  logic                      dm_resp_valid;
  logic [31:0]               dm_resp_rdata;
  logic [1:0]                dm_resp_op;
  logic                      debug_req_valid;
  logic                      debug_resp_valid;
  logic [31:0]               debug_resp_rdata;
  logic [1:0]                debug_resp_op;
  // DMI target-selection and response paths
  logic                      boot_sel;
  logic                      boot_resp_valid;
  logic [31:0]               boot_resp_rdata;
  logic [1:0]                boot_resp_op;
  logic                      sba_sel;
  logic                      sba_resp_valid;
  logic [31:0]               sba_resp_rdata;
  logic [1:0]                sba_resp_op;


  // Boot registers occupy a private DMI window. All other DMI accesses are
  // routed to the minimal debug module.
  assign debug_req_valid = dm_req_valid & !boot_sel & !sba_sel;
  assign dm_resp_valid = boot_sel ? boot_resp_valid :
                         sba_sel ? sba_resp_valid : debug_resp_valid;
  assign dm_resp_rdata = boot_sel ? boot_resp_rdata :
                         sba_sel ? sba_resp_rdata : debug_resp_rdata;
  assign dm_resp_op = boot_sel ? boot_resp_op : sba_sel ? sba_resp_op : debug_resp_op;

  sba_dmi #(
    .DMI_ADDR_WIDTH(DMI_ADDR_WIDTH)
  ) sba_dmi_i (
    // System clock/reset and incoming DMI transaction
    .clk                (clk),
    .rst_n              (rst_n),
    .dmi_req_valid_i    (dm_req_valid),
    .dmi_req_addr_i     (dm_req_addr),
    .dmi_req_wdata_i    (dm_req_wdata),
    .dmi_req_op_i       (dm_req_op),
    // Target selection and DMI response
    .dmi_req_selected_o (sba_sel),
    .dmi_resp_valid_o   (sba_resp_valid),
    .dmi_resp_rdata_o   (sba_resp_rdata),
    .dmi_resp_op_o      (sba_resp_op),
    // System-bus access transaction
    .sba_req_o          (sba_req_o),
    .sba_we_o           (sba_we_o),
    .sba_addr_o         (sba_addr_o),
    .sba_wdata_o        (sba_wdata_o),
    .sba_be_o           (sba_be_o),
    .sba_resp_valid_i   (sba_resp_valid_i),
    .sba_rdata_i        (sba_rdata_i),
    .sba_err_i          (sba_err_i)
  );

  jtag_debug_subsystem #(
    .DMI_ADDR_WIDTH(DMI_ADDR_WIDTH)
  ) jtag_debug_subsystem_i (
    // System clock/reset and JTAG TAP pins
    .clk                (clk),
    .rst_n              (rst_n),
    .jtag_tck_i         (jtag_tck_i),
    .jtag_tms_i         (jtag_tms_i),
    .jtag_tdi_i         (jtag_tdi_i),
    .jtag_tdo_o         (jtag_tdo_o),
    .jtag_trst_n_i      (jtag_trst_n_i),
    // DMI transport and routed debug-module response
    .dm_req_valid_o     (dm_req_valid),
    .dm_req_addr_o      (dm_req_addr),
    .dm_req_wdata_o     (dm_req_wdata),
    .dm_req_op_o        (dm_req_op),
    .dm_resp_valid_i    (dm_resp_valid),
    .dm_resp_rdata_i    (dm_resp_rdata),
    .dm_resp_op_i       (dm_resp_op),
    .debug_req_valid_i  (debug_req_valid),
    .debug_resp_valid_o (debug_resp_valid),
    .debug_resp_rdata_o (debug_resp_rdata),
    .debug_resp_op_o    (debug_resp_op),
    // Hart state and abstract-register access
    .hart_halt_req_o    (hart_halt_req_o),
    .hart_resume_req_o  (hart_resume_req_o),
    .hart_halted_i      (hart_halted_i),
    .hart_running_i     (hart_running_i),
    .hart_pc_i          (hart_pc_i),
    .hart_cause_i       (hart_cause_i),
    .debug_reg_req_valid_o(debug_reg_req_valid_o),
    .debug_reg_write_o  (debug_reg_write_o),
    .debug_reg_addr_o   (debug_reg_addr_o),
    .debug_reg_wdata_o  (debug_reg_wdata_o),
    .debug_reg_rdata_i  (debug_reg_rdata_i),
    .debug_reg_error_i  (debug_reg_error_i)
  );

  boot_subsystem #(
    .DMI_ADDR_WIDTH(DMI_ADDR_WIDTH),
    .IMEM_BOOT_ADDR_WIDTH(IMEM_BOOT_ADDR_WIDTH)
  ) boot_subsystem_i (
    // System clock/reset and selected boot mode
    .clk                       (clk),
    .rst_n                     (rst_n),
    .boot_mode_i               (boot_mode_i),
    // DMI boot transaction and response
    .dmi_req_valid_i           (dm_req_valid),
    .dmi_req_addr_i            (dm_req_addr),
    .dmi_req_wdata_i           (dm_req_wdata),
    .dmi_req_op_i              (dm_req_op),
    .dmi_req_selected_o        (boot_sel),
    .dmi_resp_valid_o          (boot_resp_valid),
    .dmi_resp_rdata_o          (boot_resp_rdata),
    .dmi_resp_op_o             (boot_resp_op),
    // UART boot transport and diagnostics
    .boot_uart_rx_i            (boot_uart_rx_i),
    .boot_uart_divisor_i       (boot_uart_divisor_i),
    .boot_uart_overrun_o       (boot_uart_overrun_o),
    .boot_uart_protocol_error_o(boot_uart_protocol_error_o),
    // IMEM boot-write port and fetch release
    .imem_boot_we_o            (imem_boot_we_o),
    .imem_boot_addr_o          (imem_boot_addr_o),
    .imem_boot_wdata_o         (imem_boot_wdata_o),
    .imem_boot_be_o            (imem_boot_be_o),
    .boot_fetch_enable_o       (boot_fetch_enable_o)
  );

endmodule
