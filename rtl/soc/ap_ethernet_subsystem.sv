// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// Ethernet subsystem boundary. MAC, APB control registers, DMA descriptors,
// and PHY pins are later work. Preserve its own axi_mem manager now so DMA
// never shares the hart's uncached peripheral path.
module ap_ethernet_subsystem (
  input logic clk,
  input logic rst_n,
  output logic irq_o,
  AXI_BUS.Master mem_axi_o
);

  assign irq_o = 1'b0;

  ap_axi64_idle_master dma_idle_i (
    .m_axi_o(mem_axi_o)
  );

endmodule
