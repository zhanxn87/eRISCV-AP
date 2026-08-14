// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Uncached peripheral subsystem boundary. This transition version preserves a
// physical AXI egress; the next milestone adds its address decoder, AXI-to-APB
// bridge, CLINT, PLIC, and direct interrupt outputs here.
module ap_peripheral_subsystem (
  AXI_BUS.Slave periph_axi_i,
  AXI_BUS.Master periph_axi_o
);

  ap_axi64_egress_bridge egress_i (
    .s_axi_i(periph_axi_i),
    .m_axi_o(periph_axi_o)
  );

endmodule
