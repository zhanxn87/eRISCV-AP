// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Byte-stream parser for the boot command protocol.
// UART and SPI boot share this little-endian protocol: an opcode byte followed
// by optional address/data payload bytes.
module uart_boot_slave #(
  parameter int BOOT_ADDR_WIDTH = 13
) (
  // Clock and reset
  input  logic        clk,
  input  logic        rst_n,

  // Decoded UART boot byte stream
  input  logic        uart_boot_valid_i,
  input  logic [7:0]  uart_boot_data_i,
  output logic        uart_boot_ready_o,
  output logic        protocol_error_o,

  // Command to boot-source arbitration
  output logic        boot_cmd_valid_o,
  output logic        boot_cmd_set_addr_o,
  output logic        boot_cmd_write_o,
  output logic        boot_cmd_hold_fetch_o,
  output logic        boot_cmd_release_fetch_o,
  output logic        boot_cmd_auto_inc_we_o,
  output logic        boot_cmd_auto_inc_o,
  output logic [BOOT_ADDR_WIDTH-1:0] boot_cmd_addr_o,
  output logic [31:0] boot_cmd_wdata_o,
  output logic [3:0]  boot_cmd_be_o
);


  // Opcode values are intentionally tiny and self-synchronizing only at command
  // boundaries; malformed opcode/payload sequences raise protocol_error_o.
  localparam logic [7:0] OPC_SET_ADDR   = 8'h01;
  localparam logic [7:0] OPC_WRITE32    = 8'h02;
  localparam logic [7:0] OPC_HOLD       = 8'h03;
  localparam logic [7:0] OPC_RELEASE    = 8'h04;
  localparam logic [7:0] OPC_AUTO_INC   = 8'h05;
  localparam logic [7:0] OPC_RESET_ADDR = 8'h06;

  typedef enum logic [3:0] {
    RX_OPCODE,
    RX_ADDR0,
    RX_ADDR1,
    RX_ADDR2,
    RX_ADDR3,
    RX_DATA0,
    RX_DATA1,
    RX_DATA2,
    RX_DATA3,
    RX_AUTO_INC
  } state_e;

  state_e state_q;
  logic [23:0] shift_q;

  assign uart_boot_ready_o = 1'b1;


  // The parser emits at most one boot command per received byte, clearing all
  // command pulses every cycle before consuming the next byte.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= RX_OPCODE;
      shift_q <= '0;
      protocol_error_o <= 1'b0;
      boot_cmd_valid_o <= 1'b0;
      boot_cmd_set_addr_o <= 1'b0;
      boot_cmd_write_o <= 1'b0;
      boot_cmd_hold_fetch_o <= 1'b0;
      boot_cmd_release_fetch_o <= 1'b0;
      boot_cmd_auto_inc_we_o <= 1'b0;
      boot_cmd_auto_inc_o <= 1'b0;
      boot_cmd_addr_o <= '0;
      boot_cmd_wdata_o <= 32'h0000_0000;
      boot_cmd_be_o <= 4'h0;
    end else begin
      protocol_error_o <= 1'b0;
      boot_cmd_valid_o <= 1'b0;
      boot_cmd_set_addr_o <= 1'b0;
      boot_cmd_write_o <= 1'b0;
      boot_cmd_hold_fetch_o <= 1'b0;
      boot_cmd_release_fetch_o <= 1'b0;
      boot_cmd_auto_inc_we_o <= 1'b0;
      boot_cmd_auto_inc_o <= 1'b0;
      boot_cmd_addr_o <= '0;
      boot_cmd_wdata_o <= 32'h0000_0000;
      boot_cmd_be_o <= 4'h0;

      if (uart_boot_valid_i) begin
        unique case (state_q)
          RX_OPCODE: begin
            unique case (uart_boot_data_i)
              OPC_SET_ADDR:   state_q <= RX_ADDR0;
              OPC_WRITE32:    state_q <= RX_DATA0;
              OPC_HOLD: begin
                boot_cmd_valid_o <= 1'b1;
                boot_cmd_hold_fetch_o <= 1'b1;
              end
              OPC_RELEASE: begin
                boot_cmd_valid_o <= 1'b1;
                boot_cmd_release_fetch_o <= 1'b1;
              end
              OPC_AUTO_INC:   state_q <= RX_AUTO_INC;
              OPC_RESET_ADDR: begin
                boot_cmd_valid_o <= 1'b1;
                boot_cmd_set_addr_o <= 1'b1;
                boot_cmd_addr_o <= '0;
              end
              default: begin
                protocol_error_o <= 1'b1;
              end
            endcase
          end
          RX_ADDR0: begin
            shift_q[7:0] <= uart_boot_data_i;
            state_q <= RX_ADDR1;
          end
          RX_ADDR1: begin
            shift_q[15:8] <= uart_boot_data_i;
            state_q <= RX_ADDR2;
          end
          RX_ADDR2: begin
            shift_q[23:16] <= uart_boot_data_i;
            state_q <= RX_ADDR3;
          end
          RX_ADDR3: begin
            boot_cmd_valid_o <= 1'b1;
            boot_cmd_set_addr_o <= 1'b1;
            boot_cmd_addr_o <= shift_q[BOOT_ADDR_WIDTH-1:0];
            state_q <= RX_OPCODE;
          end
          RX_DATA0: begin
            shift_q[7:0] <= uart_boot_data_i;
            state_q <= RX_DATA1;
          end
          RX_DATA1: begin
            shift_q[15:8] <= uart_boot_data_i;
            state_q <= RX_DATA2;
          end
          RX_DATA2: begin
            shift_q[23:16] <= uart_boot_data_i;
            state_q <= RX_DATA3;
          end
          RX_DATA3: begin
            boot_cmd_valid_o <= 1'b1;
            boot_cmd_write_o <= 1'b1;
            boot_cmd_wdata_o <= {uart_boot_data_i, shift_q[23:16], shift_q[15:8], shift_q[7:0]};
            boot_cmd_be_o <= 4'hf;
            state_q <= RX_OPCODE;
          end
          RX_AUTO_INC: begin
            boot_cmd_valid_o <= 1'b1;
            boot_cmd_auto_inc_we_o <= 1'b1;
            boot_cmd_auto_inc_o <= uart_boot_data_i[0];
            boot_cmd_addr_o <= '0;
            state_q <= RX_OPCODE;
          end
          default: begin
            state_q <= RX_OPCODE;
          end
        endcase
      end
    end
  end

endmodule
