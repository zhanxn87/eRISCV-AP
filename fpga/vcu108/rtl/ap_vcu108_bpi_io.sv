// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// VCU108 BPI adapter for the external-STARTUPE3 AXI EMC configuration.  The
// dedicated D[3:0], CE#, and CCLK pins are reached through STARTUPE3; D[15:4]
// use ordinary bidirectional I/O buffers.
module ap_vcu108_bpi_io (
  input logic bpi_clk_i,
  input logic [15:0] mem_dq_o_i,
  input logic [15:0] mem_dq_t_i,
  output wire [15:0] mem_dq_i_o,
  input logic mem_ce_n_i,

  input logic [25:0] mem_addr_i,
  input logic mem_oe_n_i,
  input logic mem_we_n_i,
  input logic mem_adv_n_i,
  input logic mem_reset_n_i,
  output wire mem_wait_i,

  output wire [25:0] bpi_addr_o,
  inout wire [15:4] bpi_dq_upper_io,
  output wire bpi_oe_n_o,
  output wire bpi_we_n_o,
  output wire bpi_adv_n_o,
  output wire bpi_reset_n_o,
  input wire bpi_ryby_n_i
);

  wire [3:0] bpi_dq_low_i;

  assign bpi_addr_o = mem_addr_i;
  assign bpi_oe_n_o = mem_oe_n_i;
  assign bpi_we_n_o = mem_we_n_i;
  assign bpi_adv_n_o = mem_adv_n_i;
  assign bpi_reset_n_o = mem_reset_n_i;
  assign mem_wait_i = bpi_ryby_n_i;
  assign mem_dq_i_o[3:0] = bpi_dq_low_i;

  for (genvar bit_index = 4; bit_index < 16; bit_index++) begin : g_bpi_upper_dq
    IOBUF bpi_dq_iobuf_i (
      .I(mem_dq_o_i[bit_index]),
      .T(mem_dq_t_i[bit_index]),
      .O(mem_dq_i_o[bit_index]),
      .IO(bpi_dq_upper_io[bit_index])
    );
  end

  STARTUPE3 startupe3_i (
    .CFGCLK(),
    .CFGMCLK(),
    .DI(bpi_dq_low_i),
    .DO(mem_dq_o_i[3:0]),
    .DTS(mem_dq_t_i[3:0]),
    .EOS(),
    .FCSBO(mem_ce_n_i),
    .FCSBTS(1'b0),
    .GSR(1'b0),
    .GTS(1'b0),
    .KEYCLEARB(1'b1),
    .PACK(1'b0),
    .PREQ(),
    .USRCCLKO(bpi_clk_i),
    .USRCCLKTS(1'b0),
    .USRDONEO(1'b1),
    .USRDONETS(1'b1)
  );

endmodule
