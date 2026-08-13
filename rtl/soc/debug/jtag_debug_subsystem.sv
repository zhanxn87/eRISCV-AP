// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// JTAG debug transport wrapper.
// The JTAG TAP runs in the TCK domain, dmi_cdc moves DMI requests into clk, and
// debug_module_min generates hart halt/resume requests in the SoC clock domain.
module jtag_debug_subsystem #(
  parameter int DMI_ADDR_WIDTH = 7
) (
  // System clock and reset
  input  logic                      clk,
  input  logic                      rst_n,

  // JTAG TAP pins
  input  logic                      jtag_tck_i,
  input  logic                      jtag_tms_i,
  input  logic                      jtag_tdi_i,
  output logic                      jtag_tdo_o,
  input  logic                      jtag_trst_n_i,

  // DMI transport to the debug module
  output logic                      dm_req_valid_o,
  output logic [DMI_ADDR_WIDTH-1:0] dm_req_addr_o,
  output logic [31:0]               dm_req_wdata_o,
  output logic [1:0]                dm_req_op_o,
  input  logic                      dm_resp_valid_i,
  input  logic [31:0]               dm_resp_rdata_i,
  input  logic [1:0]                dm_resp_op_i,

  // Memory-mapped DMI request/response path
  input  logic                      debug_req_valid_i,
  output logic                      debug_resp_valid_o,
  output logic [31:0]               debug_resp_rdata_o,
  output logic [1:0]                debug_resp_op_o,

  // Hart run-state and abstract-register access
  output logic                      hart_halt_req_o,
  output logic                      hart_resume_req_o,
  input  logic                      hart_halted_i,
  input  logic                      hart_running_i,
  input  logic [63:0]               hart_pc_i,
  input  logic [2:0]                hart_cause_i,
  output logic                      debug_reg_req_valid_o,
  output logic                      debug_reg_write_o,
  output logic [15:0]               debug_reg_addr_o,
  output logic [63:0]               debug_reg_wdata_o,
  input  logic [63:0]               debug_reg_rdata_i,
  input  logic                      debug_reg_error_i
);

  // JTAG-to-system DMI CDC payload
  logic                      dmi_req_toggle;
  logic [DMI_ADDR_WIDTH-1:0] dmi_req_addr;
  logic [31:0]               dmi_req_wdata;
  logic [1:0]                dmi_req_op;
  // System-to-JTAG DMI CDC payload
  logic                      dmi_resp_toggle;
  logic [31:0]               dmi_resp_rdata;
  logic [1:0]                dmi_resp_op;


  // The DTM only understands the JTAG serial protocol; DMI request/response CDC
  // is handled below so the debug module itself remains single-clocked.
  jtag_dtm #(
    .DMI_ADDR_WIDTH(DMI_ADDR_WIDTH)
  ) jtag_dtm_i (
    // JTAG TAP pins
    .tck_i             (jtag_tck_i),
    .trst_n_i          (jtag_trst_n_i),
    .tms_i             (jtag_tms_i),
    .tdi_i             (jtag_tdi_i),
    .tdo_o             (jtag_tdo_o),
    // Toggle-based DMI transport in the TCK domain
    .dmi_req_toggle_o  (dmi_req_toggle),
    .dmi_req_addr_o    (dmi_req_addr),
    .dmi_req_wdata_o   (dmi_req_wdata),
    .dmi_req_op_o      (dmi_req_op),
    .dmi_resp_toggle_i (dmi_resp_toggle),
    .dmi_resp_rdata_i  (dmi_resp_rdata),
    .dmi_resp_op_i     (dmi_resp_op)
  );

  dmi_cdc #(
    .DMI_ADDR_WIDTH(DMI_ADDR_WIDTH)
  ) dmi_cdc_i (
    // System clock/reset
    .clk                  (clk),
    .rst_n                (rst_n),
    // JTAG-domain DMI request and response payloads
    .dmi_req_toggle_tck_i (dmi_req_toggle),
    .dmi_req_addr_tck_i   (dmi_req_addr),
    .dmi_req_wdata_tck_i  (dmi_req_wdata),
    .dmi_req_op_tck_i     (dmi_req_op),
    .dmi_resp_toggle_tck_o(dmi_resp_toggle),
    .dmi_resp_rdata_tck_o (dmi_resp_rdata),
    .dmi_resp_op_tck_o    (dmi_resp_op),
    // System-domain debug-module transaction
    .dm_req_valid_o       (dm_req_valid_o),
    .dm_req_addr_o        (dm_req_addr_o),
    .dm_req_wdata_o       (dm_req_wdata_o),
    .dm_req_op_o          (dm_req_op_o),
    .dm_resp_valid_i      (dm_resp_valid_i),
    .dm_resp_rdata_i      (dm_resp_rdata_i),
    .dm_resp_op_i         (dm_resp_op_i)
  );

  debug_module_min #(
    .DMI_ADDR_WIDTH(DMI_ADDR_WIDTH)
  ) debug_module_i (
    // System clock/reset and routed DMI transaction
    .clk              (clk),
    .rst_n            (rst_n),
    .dmi_req_valid_i  (debug_req_valid_i),
    .dmi_req_addr_i   (dm_req_addr_o),
    .dmi_req_wdata_i  (dm_req_wdata_o),
    .dmi_req_op_i     (dm_req_op_o),
    // Debug-module DMI response
    .dmi_resp_valid_o (debug_resp_valid_o),
    .dmi_resp_rdata_o (debug_resp_rdata_o),
    .dmi_resp_op_o    (debug_resp_op_o),
    // Hart state and abstract-register access
    .hart_halt_req_o  (hart_halt_req_o),
    .hart_resume_req_o(hart_resume_req_o),
    .hart_halted_i    (hart_halted_i),
    .hart_running_i   (hart_running_i),
    .hart_pc_i        (hart_pc_i),
    .hart_cause_i     (hart_cause_i),
    .debug_reg_req_valid_o(debug_reg_req_valid_o),
    .debug_reg_write_o(debug_reg_write_o),
    .debug_reg_addr_o(debug_reg_addr_o),
    .debug_reg_wdata_o(debug_reg_wdata_o),
    .debug_reg_rdata_i(debug_reg_rdata_i),
    .debug_reg_error_i(debug_reg_error_i)
  );

endmodule
