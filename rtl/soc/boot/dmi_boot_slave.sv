// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// DMI-facing boot register block.
// A debugger can set the boot address, write instruction words, hold/release
// fetch, and read loader status through a small private DMI register window.
module dmi_boot_slave #(
  parameter int DMI_ADDR_WIDTH = 7,
  parameter int BOOT_ADDR_WIDTH = 13
) (
  // DMI request/response transaction
  input  logic                      dmi_req_valid_i,
  input  logic [DMI_ADDR_WIDTH-1:0] dmi_req_addr_i,
  input  logic [31:0]               dmi_req_wdata_i,
  input  logic [1:0]                dmi_req_op_i,
  output logic                      dmi_req_selected_o,
  output logic                      dmi_resp_valid_o,
  output logic [31:0]               dmi_resp_rdata_o,
  output logic [1:0]                dmi_resp_op_o,

  // Current IMEM boot-controller state
  input  logic [BOOT_ADDR_WIDTH-1:0] boot_current_addr_i,
  input  logic                      boot_auto_inc_i,
  input  logic                      boot_fetch_released_i,

  // Decoded command to boot-source arbitration
  output logic                      boot_cmd_valid_o,
  output logic                      boot_cmd_set_addr_o,
  output logic                      boot_cmd_write_o,
  output logic                      boot_cmd_hold_fetch_o,
  output logic                      boot_cmd_release_fetch_o,
  output logic                      boot_cmd_auto_inc_we_o,
  output logic                      boot_cmd_auto_inc_o,
  output logic [BOOT_ADDR_WIDTH-1:0] boot_cmd_addr_o,
  output logic [31:0]               boot_cmd_wdata_o,
  output logic [3:0]                boot_cmd_be_o
);


  // Register map is kept in the debug DMI address space so the external JTAG
  // transport and the boot loader do not need separate board pins.
  localparam logic [DMI_ADDR_WIDTH-1:0] REG_BOOT_ADDR   = 7'h60;
  localparam logic [DMI_ADDR_WIDTH-1:0] REG_BOOT_WDATA  = 7'h61;
  localparam logic [DMI_ADDR_WIDTH-1:0] REG_BOOT_CTRL   = 7'h62;
  localparam logic [DMI_ADDR_WIDTH-1:0] REG_BOOT_STATUS = 7'h63;

  localparam logic [1:0] DMI_OP_NOP   = 2'b00;
  localparam logic [1:0] DMI_OP_READ  = 2'b01;
  localparam logic [1:0] DMI_OP_WRITE = 2'b10;
  localparam logic [1:0] DMI_RESP_OK  = 2'b00;
  localparam logic [1:0] DMI_RESP_ERR = 2'b10;

  assign dmi_req_selected_o = (dmi_req_addr_i == REG_BOOT_ADDR) ||
                              (dmi_req_addr_i == REG_BOOT_WDATA) ||
                              (dmi_req_addr_i == REG_BOOT_CTRL) ||
                              (dmi_req_addr_i == REG_BOOT_STATUS);


  // Reads always return a response for selected registers. Writes emit one boot
  // command pulse; invalid DMI opcodes return an error response.
  always_comb begin
    dmi_resp_valid_o = 1'b0;
    dmi_resp_rdata_o = 32'h0000_0000;
    dmi_resp_op_o = DMI_RESP_OK;

    boot_cmd_valid_o = 1'b0;
    boot_cmd_set_addr_o = 1'b0;
    boot_cmd_write_o = 1'b0;
    boot_cmd_hold_fetch_o = 1'b0;
    boot_cmd_release_fetch_o = 1'b0;
    boot_cmd_auto_inc_we_o = 1'b0;
    boot_cmd_auto_inc_o = 1'b0;
    boot_cmd_addr_o = '0;
    boot_cmd_wdata_o = 32'h0000_0000;
    boot_cmd_be_o = 4'h0;

    if (dmi_req_valid_i && dmi_req_selected_o) begin
      dmi_resp_valid_o = 1'b1;

      unique case (dmi_req_addr_i)
        REG_BOOT_ADDR: begin
          dmi_resp_rdata_o = {{(32-BOOT_ADDR_WIDTH){1'b0}}, boot_current_addr_i};
        end
        REG_BOOT_CTRL,
        REG_BOOT_STATUS: begin
          // bit 3 records the fixed reset policy: non-bypass boot holds fetch.
          dmi_resp_rdata_o = {28'd0, 1'b1, boot_auto_inc_i, boot_fetch_released_i, 1'b1};
        end
        default: begin
          dmi_resp_rdata_o = 32'h0000_0000;
        end
      endcase

      if (!((dmi_req_op_i == DMI_OP_READ) || (dmi_req_op_i == DMI_OP_WRITE) || (dmi_req_op_i == DMI_OP_NOP))) begin
        dmi_resp_op_o = DMI_RESP_ERR;
      end

      if (dmi_req_op_i == DMI_OP_WRITE) begin
        unique case (dmi_req_addr_i)
          REG_BOOT_ADDR: begin
            boot_cmd_valid_o = 1'b1;
            boot_cmd_set_addr_o = 1'b1;
            boot_cmd_addr_o = dmi_req_wdata_i[BOOT_ADDR_WIDTH-1:0];
          end
          REG_BOOT_WDATA: begin
            boot_cmd_valid_o = 1'b1;
            boot_cmd_write_o = 1'b1;
            boot_cmd_wdata_o = dmi_req_wdata_i;
            boot_cmd_be_o = 4'hf;
          end
          REG_BOOT_CTRL: begin
            boot_cmd_valid_o = 1'b1;
            boot_cmd_auto_inc_we_o = 1'b1;
            boot_cmd_auto_inc_o = dmi_req_wdata_i[2];
            boot_cmd_set_addr_o = dmi_req_wdata_i[3];
            boot_cmd_addr_o = '0;
            boot_cmd_hold_fetch_o = dmi_req_wdata_i[1];
            boot_cmd_release_fetch_o = dmi_req_wdata_i[0];
          end
          default: begin
          end
        endcase
      end
    end
  end

endmodule
