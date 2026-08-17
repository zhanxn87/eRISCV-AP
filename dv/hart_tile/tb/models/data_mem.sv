// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// DBus adapter for the portable single-port data SRAM.
module data_mem #(
  parameter ADDR_WIDTH = 13,
  parameter DATA_WIDTH = 32,
  parameter BYTE_LANES = DATA_WIDTH / 8,
  parameter READ_LATENCY = 1
) (
  // Clock and reset
  input  logic                  clk,
  input  logic                  rst_n,

  // Single-port SRAM request/response transaction
  input  logic                  req_i,
  input  logic                  we_i,
  input  logic [BYTE_LANES-1:0] be_i,
  input  logic [ADDR_WIDTH-1:0] addr_i,
  input  logic [DATA_WIDTH-1:0] wdata_i,
  // RV64A operation encoding from riscv_pkg::atomic_op_e.  This module keeps
  // the encoding local so it remains usable below the core package layer.
  input  logic [3:0]            atomic_op_i,
  output logic                  resp_valid_o,
  output logic                  resp_write_o,
  output logic [DATA_WIDTH-1:0] rdata_o,
  output logic                  err_o
);

  localparam logic [3:0] ATOMIC_NONE = 4'd0;
  localparam logic [3:0] ATOMIC_LR   = 4'd1;
  localparam logic [3:0] ATOMIC_SC   = 4'd2;
  localparam logic [3:0] ATOMIC_SWAP = 4'd3;
  localparam logic [3:0] ATOMIC_ADD  = 4'd4;
  localparam logic [3:0] ATOMIC_XOR  = 4'd5;
  localparam logic [3:0] ATOMIC_AND  = 4'd6;
  localparam logic [3:0] ATOMIC_OR   = 4'd7;
  localparam logic [3:0] ATOMIC_MIN  = 4'd8;
  localparam logic [3:0] ATOMIC_MAX  = 4'd9;
  localparam logic [3:0] ATOMIC_MINU = 4'd10;
  localparam logic [3:0] ATOMIC_MAXU = 4'd11;

  typedef enum logic [1:0] {
    ATOMIC_IDLE,
    ATOMIC_READ_WAIT,
    ATOMIC_WRITE,
    ATOMIC_RESP
  } atomic_state_e;

  // SRAM response and registered completion pipeline
  logic sram_resp_valid;
  logic [DATA_WIDTH-1:0] sram_rdata;
  logic [DATA_WIDTH-1:0] normal_rdata;
  logic [READ_LATENCY-1:0] resp_valid_pipe_q;
  logic [READ_LATENCY-1:0] resp_write_pipe_q;
  logic [READ_LATENCY-1:0] atomic_read_pipe_q;
  integer index;

  logic normal_req;
  logic atomic_req;
  logic atomic_read_issue;
  logic atomic_write_issue;
  logic atomic_sc_success_i;
  logic atomic_read_done;
  atomic_state_e atomic_state_q;
  logic [3:0] atomic_op_q;
  logic [ADDR_WIDTH-1:0] atomic_addr_q;
  logic [DATA_WIDTH-1:0] atomic_wdata_q;
  logic [BYTE_LANES-1:0] atomic_be_q;
  logic [DATA_WIDTH-1:0] atomic_old_q;
  logic atomic_sc_success_q;
  logic reservation_valid_q;
  logic [ADDR_WIDTH-1:0] reservation_addr_q;
  logic reservation_word_q;
  logic reservation_high_q;
  logic atomic_word_q;
  logic atomic_high_q;
  logic [31:0] atomic_old_word;
  logic [31:0] atomic_operand_word;
  logic [31:0] atomic_new_word;
  logic [DATA_WIDTH-1:0] atomic_write_data;
  logic [BYTE_LANES-1:0] atomic_write_be;

  sram_1rw #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) sram_i (
    .clk    (clk),
    .en_i   (normal_req || atomic_read_issue || atomic_write_issue),
    .we_i   ((normal_req && we_i) || atomic_write_issue),
    .be_i   (atomic_write_issue ? atomic_write_be : be_i),
    .addr_i (atomic_write_issue ? atomic_addr_q : addr_i),
    .wdata_i(atomic_write_issue ? atomic_write_data : wdata_i),
    .rdata_o(sram_rdata)
  );

  assign normal_req = req_i && (atomic_op_i == ATOMIC_NONE);
  assign atomic_req = req_i && (atomic_op_i != ATOMIC_NONE) &&
                      (atomic_state_q == ATOMIC_IDLE);
  assign atomic_word_q = (atomic_be_q != {BYTE_LANES{1'b1}});
  assign atomic_high_q = atomic_word_q && atomic_be_q[BYTE_LANES-1];
  assign atomic_sc_success_i = reservation_valid_q &&
                               (reservation_addr_q == addr_i) &&
                               (reservation_word_q == (be_i != {BYTE_LANES{1'b1}})) &&
                               (!reservation_word_q || (reservation_high_q == be_i[BYTE_LANES-1]));
  assign atomic_read_issue = atomic_req && !((atomic_op_i == ATOMIC_SC) && !atomic_sc_success_i);
  assign atomic_write_issue = (atomic_state_q == ATOMIC_WRITE);
  assign atomic_read_done = atomic_read_pipe_q[READ_LATENCY-1];

  always_comb begin
    atomic_old_word = atomic_high_q ? atomic_old_q[DATA_WIDTH-1 -: 32] : atomic_old_q[31:0];
    atomic_operand_word = atomic_high_q ? atomic_wdata_q[DATA_WIDTH-1 -: 32] : atomic_wdata_q[31:0];
    atomic_new_word = atomic_operand_word;
    unique case (atomic_op_q)
      ATOMIC_SC,
      ATOMIC_SWAP: atomic_new_word = atomic_operand_word;
      ATOMIC_ADD:  atomic_new_word = atomic_old_word + atomic_operand_word;
      ATOMIC_XOR:  atomic_new_word = atomic_old_word ^ atomic_operand_word;
      ATOMIC_AND:  atomic_new_word = atomic_old_word & atomic_operand_word;
      ATOMIC_OR:   atomic_new_word = atomic_old_word | atomic_operand_word;
      ATOMIC_MIN:  atomic_new_word = ($signed(atomic_old_word) < $signed(atomic_operand_word)) ? atomic_old_word : atomic_operand_word;
      ATOMIC_MAX:  atomic_new_word = ($signed(atomic_old_word) > $signed(atomic_operand_word)) ? atomic_old_word : atomic_operand_word;
      ATOMIC_MINU: atomic_new_word = (atomic_old_word < atomic_operand_word) ? atomic_old_word : atomic_operand_word;
      ATOMIC_MAXU: atomic_new_word = (atomic_old_word > atomic_operand_word) ? atomic_old_word : atomic_operand_word;
      default: ;
    endcase
    atomic_write_data = atomic_old_q;
    atomic_write_be = atomic_be_q;
    if (atomic_word_q) begin
      if (atomic_high_q)
        atomic_write_data[DATA_WIDTH-1 -: 32] = atomic_new_word;
      else
        atomic_write_data[31:0] = atomic_new_word;
    end else begin
      unique case (atomic_op_q)
        ATOMIC_SC,
        ATOMIC_SWAP: atomic_write_data = atomic_wdata_q;
        ATOMIC_ADD:  atomic_write_data = atomic_old_q + atomic_wdata_q;
        ATOMIC_XOR:  atomic_write_data = atomic_old_q ^ atomic_wdata_q;
        ATOMIC_AND:  atomic_write_data = atomic_old_q & atomic_wdata_q;
        ATOMIC_OR:   atomic_write_data = atomic_old_q | atomic_wdata_q;
        ATOMIC_MIN:  atomic_write_data = ($signed(atomic_old_q) < $signed(atomic_wdata_q)) ? atomic_old_q : atomic_wdata_q;
        ATOMIC_MAX:  atomic_write_data = ($signed(atomic_old_q) > $signed(atomic_wdata_q)) ? atomic_old_q : atomic_wdata_q;
        ATOMIC_MINU: atomic_write_data = (atomic_old_q < atomic_wdata_q) ? atomic_old_q : atomic_wdata_q;
        ATOMIC_MAXU: atomic_write_data = (atomic_old_q > atomic_wdata_q) ? atomic_old_q : atomic_wdata_q;
        default: ;
      endcase
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      resp_valid_pipe_q <= '0;
      resp_write_pipe_q <= '0;
    end else begin
      resp_valid_pipe_q[0] <= normal_req;
      resp_write_pipe_q[0] <= normal_req && we_i;
      atomic_read_pipe_q[0] <= atomic_read_issue;
      for (index = 1; index < READ_LATENCY; index = index + 1) begin
        resp_valid_pipe_q[index] <= resp_valid_pipe_q[index-1];
        resp_write_pipe_q[index] <= resp_write_pipe_q[index-1];
        atomic_read_pipe_q[index] <= atomic_read_pipe_q[index-1];
      end
    end
  end

  generate
    if (READ_LATENCY == 1) begin : gen_one_cycle_read
      assign normal_rdata = sram_rdata;
    end else begin : gen_extra_read_latency
      logic [DATA_WIDTH-1:0] rdata_pipe_q [0:READ_LATENCY-2];
      integer pipe_index;

      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          for (pipe_index = 0; pipe_index < READ_LATENCY-1; pipe_index = pipe_index + 1) begin
            rdata_pipe_q[pipe_index] <= '0;
          end
        end else begin
          rdata_pipe_q[0] <= sram_rdata;
          for (pipe_index = 1; pipe_index < READ_LATENCY-1; pipe_index = pipe_index + 1) begin
            rdata_pipe_q[pipe_index] <= rdata_pipe_q[pipe_index-1];
          end
        end
      end

      assign normal_rdata = rdata_pipe_q[READ_LATENCY-2];
    end
  endgenerate

  assign sram_resp_valid = resp_valid_pipe_q[READ_LATENCY-1];
  assign resp_valid_o = (atomic_state_q == ATOMIC_RESP) || sram_resp_valid;
  assign resp_write_o = (atomic_state_q == ATOMIC_RESP) ? 1'b0 : resp_write_pipe_q[READ_LATENCY-1];
  assign err_o        = 1'b0;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      atomic_state_q <= ATOMIC_IDLE;
      atomic_op_q <= ATOMIC_NONE;
      atomic_addr_q <= '0;
      atomic_wdata_q <= '0;
      atomic_be_q <= '0;
      atomic_old_q <= '0;
      atomic_sc_success_q <= 1'b0;
      reservation_valid_q <= 1'b0;
      reservation_addr_q <= '0;
      reservation_word_q <= 1'b0;
      reservation_high_q <= 1'b0;
    end else begin
      if (normal_req && we_i)
        reservation_valid_q <= 1'b0;

      unique case (atomic_state_q)
        ATOMIC_IDLE: begin
          if (atomic_req) begin
            atomic_op_q <= atomic_op_i;
            atomic_addr_q <= addr_i;
            atomic_wdata_q <= wdata_i;
            atomic_be_q <= be_i;
            atomic_sc_success_q <= (atomic_op_i == ATOMIC_SC) && atomic_sc_success_i;
            if ((atomic_op_i == ATOMIC_SC) && !atomic_sc_success_i) begin
              reservation_valid_q <= 1'b0;
              atomic_state_q <= ATOMIC_RESP;
            end else begin
              atomic_state_q <= ATOMIC_READ_WAIT;
            end
          end
        end
        ATOMIC_READ_WAIT: begin
          if (atomic_read_done) begin
            atomic_old_q <= normal_rdata;
            if (atomic_op_q == ATOMIC_LR) begin
              reservation_valid_q <= 1'b1;
              reservation_addr_q <= atomic_addr_q;
              reservation_word_q <= atomic_word_q;
              reservation_high_q <= atomic_high_q;
              atomic_state_q <= ATOMIC_RESP;
            end else begin
              atomic_state_q <= ATOMIC_WRITE;
            end
          end
        end
        ATOMIC_WRITE: begin
          reservation_valid_q <= 1'b0;
          atomic_state_q <= ATOMIC_RESP;
        end
        ATOMIC_RESP: atomic_state_q <= ATOMIC_IDLE;
        default: atomic_state_q <= ATOMIC_IDLE;
      endcase
    end
  end

  always_comb begin
    if (atomic_state_q == ATOMIC_RESP) begin
      rdata_o = (atomic_op_q == ATOMIC_SC) ?
                {{(DATA_WIDTH-1){1'b0}}, !atomic_sc_success_q} : atomic_old_q;
    end else begin
      rdata_o = normal_rdata;
    end
  end

endmodule
