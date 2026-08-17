// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// RISC-V C (Compressed) Extension Decompressor for RV64.
// Converts 16-bit compressed instructions to their 32-bit equivalents.
// C instructions are identified by bits [1:0] != 2'b11.
//
// Integer RV64C instructions are supported; FP compressed encodings stay
// illegal until the RV64D datapath is implemented.
// Reserved compressed encodings are marked as illegal.
/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off WIDTHEXPAND */
module c_decompressor (
  input  logic [15:0] c_instr_i,
  output logic [31:0] instr_o,
  output logic        illegal_o
);

  logic [2:0] funct3;
  logic [1:0] op;

  assign op     = c_instr_i[1:0];
  assign funct3 = c_instr_i[15:13];

  always_comb begin
    instr_o   = 32'h0000_0013;  // default: nop
    illegal_o = 1'b0;

    unique case (op)
      2'b00: begin  // C0: register-based operations + loads/stores
        unique case (funct3)
          3'b000: begin  // c.addi4spn -> addi rd', x2, nzuimm
            if (c_instr_i[12:5] == 8'h00) begin
              illegal_o = 1'b1;  // nzuimm == 0 is reserved
            end else begin
              instr_o = {
                2'b00, c_instr_i[10:7], c_instr_i[12:11], c_instr_i[5],
                c_instr_i[6], 2'b00, 5'b00010, 3'b000,
                2'b01, c_instr_i[4:2], 7'b0010011
              };
            end
          end
          3'b010: begin  // c.lw -> lw rd', offset[5:3](rs1') with offset[2:0]=0, offset[5:3] in instr
            // offset = uimm[5:3],uimm[2]+uimm[6],00 ; uimm[5:3]={c[5],c[12:10]}, uimm[2]=c[6], uimm[6]=c[5]
            instr_o = {
                5'b00000, c_instr_i[5], c_instr_i[12:10], c_instr_i[6],
                2'b00, 2'b01, c_instr_i[9:7], 3'b010,
                2'b01, c_instr_i[4:2], 7'b0000011
            };
          end
          3'b011: begin  // c.ld -> ld rd', offset[7:3](rs1')
            instr_o = {
                4'b0000, c_instr_i[6:5], c_instr_i[12:10], 3'b000,
                2'b01, c_instr_i[9:7], 3'b011,
                2'b01, c_instr_i[4:2], 7'b0000011
            };
          end
          3'b110: begin  // c.sw -> sw rs2', offset[6:2](rs1')
            instr_o = {
                5'b00000, c_instr_i[5], c_instr_i[12],
                2'b01, c_instr_i[4:2], 2'b01, c_instr_i[9:7], 3'b010,
                c_instr_i[11:10], c_instr_i[6], 2'b00, 7'b0100011
            };
          end
          3'b111: begin  // c.sd -> sd rs2', offset[7:3](rs1')
            instr_o = {
                4'b0000, c_instr_i[6:5], c_instr_i[12],
                2'b01, c_instr_i[4:2], 2'b01, c_instr_i[9:7], 3'b011,
                c_instr_i[11:10], 3'b000, 7'b0100011
            };
          end
          default: begin
            illegal_o = 1'b1;
          end
        endcase
      end

      2'b01: begin  // C1: immediate + control transfer
        unique case (funct3)
          3'b000: begin  // c.addi / c.nop
            if (c_instr_i[11:7] == 5'd0) begin
              // c.nop: addi x0, x0, 0 = HINT, not illegal
              instr_o = {7'b0000000, 5'd0, 5'd0, 3'b000, 5'd0, 7'b0010011};
            end else begin
              // c.addi rd, rd, nzimm[5:0]
              instr_o = {
                {6{c_instr_i[12]}}, c_instr_i[12], c_instr_i[6:2],
                c_instr_i[11:7], 3'b000, c_instr_i[11:7], 7'b0010011
              };
            end
          end
          3'b001: begin  // c.addiw -> addiw rd, rd, nzimm
            if (c_instr_i[11:7] == 5'd0) begin
              illegal_o = 1'b1;
            end else begin
              instr_o = {
                  {6{c_instr_i[12]}}, c_instr_i[12], c_instr_i[6:2],
                  c_instr_i[11:7], 3'b000, c_instr_i[11:7], 7'b0011011
              };
            end
          end
          3'b010: begin  // c.li -> addi rd, x0, nzimm (rd=x0 is a HINT)
            if (c_instr_i[11:7] == 5'd0) begin
              // c.li x0, imm is a HINT and has no architectural effect.
              instr_o = 32'h0000_0013;
            end else begin
              instr_o = {
                {6{c_instr_i[12]}}, c_instr_i[12], c_instr_i[6:2],
                5'd0, 3'b000, c_instr_i[11:7], 7'b0010011
              };
            end
          end
          3'b011: begin  // c.lui / c.addi16sp
            if (c_instr_i[11:7] == 5'd2) begin
              // c.addi16sp: addi x2, x2, nzimm[9:4]
              instr_o = {
                {3{c_instr_i[12]}}, c_instr_i[4:3], c_instr_i[5],
                c_instr_i[2], c_instr_i[6], 4'b0000, 5'b00010,
                3'b000, 5'b00010, 7'b0010011
              };
            end else if (c_instr_i[11:7] != 5'd0) begin
              // c.lui rd, nzimm[17:12] (rd != {x0, x2})
              instr_o = {
                {14{c_instr_i[12]}}, c_instr_i[12], c_instr_i[6:2],
                c_instr_i[11:7], 7'b0110111
              };
            end
          end
          3'b100: begin  // ALU ops with register operands (C.MV not here)
            logic [1:0] op_sel;
            op_sel = c_instr_i[11:10];
            unique case (op_sel)
              2'b00: begin  // c.srli
                instr_o = {
                    6'b000000, c_instr_i[12], c_instr_i[6:2], 2'b01, c_instr_i[9:7],
                    3'b101, 2'b01, c_instr_i[9:7], 7'b0010011
                };
              end
              2'b01: begin  // c.srai
                instr_o = {
                    6'b010000, c_instr_i[12], c_instr_i[6:2], 2'b01, c_instr_i[9:7],
                    3'b101, 2'b01, c_instr_i[9:7], 7'b0010011
                };
              end
              2'b10: begin  // c.andi
                instr_o = {
                    {6{c_instr_i[12]}}, c_instr_i[12], c_instr_i[6:2],
                    2'b01, c_instr_i[9:7], 3'b111,
                    2'b01, c_instr_i[9:7], 7'b0010011
                };
              end
              2'b11: begin  // c.sub*/c.xor/c.or/c.and based on bits [6:5]
                logic [1:0] sub_op;
                sub_op = c_instr_i[6:5];
                if (c_instr_i[12]) begin
                  case (sub_op)
                    2'b00: instr_o = {7'b0100000, 2'b01, c_instr_i[4:2], 2'b01, c_instr_i[9:7], 3'b000, 2'b01, c_instr_i[9:7], 7'b0111011}; // c.subw
                    2'b01: instr_o = {7'b0000000, 2'b01, c_instr_i[4:2], 2'b01, c_instr_i[9:7], 3'b000, 2'b01, c_instr_i[9:7], 7'b0111011}; // c.addw
                    default: illegal_o = 1'b1;
                  endcase
                end else begin
                  case (sub_op)
                    2'b00: instr_o = {7'b0100000, 2'b01, c_instr_i[4:2], 2'b01, c_instr_i[9:7], 3'b000, 2'b01, c_instr_i[9:7], 7'b0110011}; // c.sub
                    2'b01: instr_o = {7'b0000000, 2'b01, c_instr_i[4:2], 2'b01, c_instr_i[9:7], 3'b100, 2'b01, c_instr_i[9:7], 7'b0110011}; // c.xor
                    2'b10: instr_o = {7'b0000000, 2'b01, c_instr_i[4:2], 2'b01, c_instr_i[9:7], 3'b110, 2'b01, c_instr_i[9:7], 7'b0110011}; // c.or
                    2'b11: instr_o = {7'b0000000, 2'b01, c_instr_i[4:2], 2'b01, c_instr_i[9:7], 3'b111, 2'b01, c_instr_i[9:7], 7'b0110011}; // c.and
                  endcase
                end
              end
            endcase
          end
          3'b101: begin  // c.j -> jal x0, offset
            instr_o = {
                c_instr_i[12], c_instr_i[8], c_instr_i[10:9], c_instr_i[6],
                c_instr_i[7], c_instr_i[2], c_instr_i[11], c_instr_i[5:3],
                {9{c_instr_i[12]}}, 5'd0, 7'b1101111
            };
          end
          3'b110: begin  // c.beqz -> beq rs1', x0, offset
            instr_o = {
                // CB offset is imm[8|4:3|7:6|2:1|5].  Reorder it into
                // the B-format imm[12|10:5|4:1|11] layout.
                {4{c_instr_i[12]}}, c_instr_i[6:5], c_instr_i[2],
                5'd0, 2'b01, c_instr_i[9:7], 3'b000,
                c_instr_i[11:10], c_instr_i[4:3], c_instr_i[12], 7'b1100011
            };
          end
          3'b111: begin  // c.bnez -> bne rs1', x0, offset
            instr_o = {
                {4{c_instr_i[12]}}, c_instr_i[6:5], c_instr_i[2],
                5'd0, 2'b01, c_instr_i[9:7], 3'b001,
                c_instr_i[11:10], c_instr_i[4:3], c_instr_i[12], 7'b1100011
            };
          end
          default: begin
            illegal_o = 1'b1;
          end
        endcase
      end

      2'b10: begin  // C2: stack-relative + register moves + control
        unique case (funct3)
          3'b000: begin  // c.slli (rd=x0 is a HINT)
            if (c_instr_i[11:7] == 5'd0) begin
              // c.slli x0, shamt is a HINT and has no architectural effect.
              instr_o = 32'h0000_0013;
            end else begin
              instr_o = {
                6'b000000, c_instr_i[12], c_instr_i[6:2], c_instr_i[11:7],
                3'b001, c_instr_i[11:7], 7'b0010011
              };
            end
          end
          3'b010: begin  // c.lwsp -> lw rd, offset[7:2](x2) (rd != x0)
            if (c_instr_i[11:7] == 5'd0) begin
              illegal_o = 1'b1;
            end else begin
              instr_o = {
                4'b0000, c_instr_i[3:2], c_instr_i[12], c_instr_i[6:4], 2'b00,
                5'b00010, 3'b010, c_instr_i[11:7], 7'b0000011
              };
            end
          end
          3'b011: begin  // c.ldsp -> ld rd, offset[8:3](x2)
            instr_o = {
                3'b000, c_instr_i[4:2], c_instr_i[12], c_instr_i[6:5], 3'b000,
                5'b00010, 3'b011, c_instr_i[11:7], 7'b0000011
            };
          end
          3'b100: begin  // c.jr/c.mv/c.ebreak/c.jalr/c.add
            if (c_instr_i[12] == 1'b0) begin
              if (c_instr_i[6:2] == 5'd0 && c_instr_i[11:7] != 5'd0) begin
                // c.jr: jalr x0, rs1, 0 (rs1 != x0)
                instr_o = {12'd0, c_instr_i[11:7], 3'b000, 5'd0, 7'b1100111};
              end else if (c_instr_i[6:2] != 5'd0 && c_instr_i[11:7] != 5'd0) begin
                // c.mv: add rd, x0, rs2 (rd != x0, rs2 != x0)
                instr_o = {7'b0000000, c_instr_i[6:2], 5'd0, 3'b000, c_instr_i[11:7], 7'b0110011};
              end
            end else begin
              if (c_instr_i[6:2] == 5'd0 && c_instr_i[11:7] == 5'd0) begin
                // c.ebreak
                instr_o = {12'h001, 5'd0, 3'b000, 5'd0, 7'b1110011};  // ebreak
              end else if (c_instr_i[6:2] == 5'd0 && c_instr_i[11:7] != 5'd0) begin
                // c.jalr: jalr x1, rs1, 0
                instr_o = {12'd0, c_instr_i[11:7], 3'b000, 5'b00001, 7'b1100111};
              end else if (c_instr_i[6:2] != 5'd0 && c_instr_i[11:7] != 5'd0) begin
                // c.add: add rd, rd, rs2 (rd != x0, rs2 != x0)
                instr_o = {7'b0000000, c_instr_i[6:2], c_instr_i[11:7], 3'b000, c_instr_i[11:7], 7'b0110011};
              end
            end
          end
          3'b110: begin  // c.swsp -> sw rs2, offset[7:2](x2)
            instr_o = {
                4'b0000, c_instr_i[8:7], c_instr_i[12], c_instr_i[6:2],
                5'b00010, 3'b010, c_instr_i[11:9], 2'b00, 7'b0100011
            };
          end
          3'b111: begin  // c.sdsp -> sd rs2, offset[8:3](x2)
            instr_o = {
                3'b000, c_instr_i[9:7], c_instr_i[12], c_instr_i[6:2],
                5'b00010, 3'b011, c_instr_i[11:10], 3'b000, 7'b0100011
            };
          end
          default: begin
            illegal_o = 1'b1;
          end
        endcase
      end

      default: begin  // op == 2'b11 -> 32-bit instruction, should not be here
        illegal_o = 1'b1;
      end
    endcase
  end

endmodule
