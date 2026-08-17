// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// AP architectural constants. The AP SoC top and its verification manifest
// use this package exclusively; no 32-bit TCM address map is in the AP build.
package ap_soc_pkg;

  localparam int unsigned AP_HART_COUNT        = 1;
  localparam int unsigned AP_PADDR_W           = 48;
  localparam int unsigned AP_AXI_DATA_W        = 64;
  localparam int unsigned AP_AXI_SLV_ID_W      = 4;
  localparam int unsigned AP_AXI_USER_W        = 1;
  // Cacheable-memory AXI plane: I-Cache, D-Cache, and Ethernet DMA share
  // one DDR-facing crossbar.  Its route bits never leave ap_axi_mem_xbar.
  localparam int unsigned AP_AXI_MEM_INGRESS_PORTS = 3;
  localparam int unsigned AP_AXI_MEM_EGRESS_PORTS  = 2;
  localparam int unsigned AP_AXI_MEM_MST_ID_W      = AP_AXI_SLV_ID_W + $clog2(AP_AXI_MEM_INGRESS_PORTS);
  localparam int unsigned AP_AXI_MEM_MAX_OUTSTANDING = 8;

  localparam int unsigned AP_AXI_MEM_INGRESS_ICACHE  = 0;
  localparam int unsigned AP_AXI_MEM_INGRESS_DCACHE  = 1;
  localparam int unsigned AP_AXI_MEM_INGRESS_ETH_DMA = 2;
  localparam int unsigned AP_AXI_MEM_EGRESS_DDR      = 0;
  // axi_mem never owns MMIO. This local terminator makes an accidental
  // non-DDR request complete with DECERR instead of entering axi_periph.
  localparam int unsigned AP_AXI_MEM_EGRESS_ERROR = 1;

  // Uncached-device AXI plane.  The current single hart contributes one
  // manager; ap_axi_periph_xbar is the expansion point for additional harts.
  localparam int unsigned AP_AXI_PERIPH_INGRESS_PORTS = 1;
  localparam int unsigned AP_AXI_PERIPH_EGRESS_PORTS  = 2;
  localparam int unsigned AP_AXI_PERIPH_MST_ID_W = AP_AXI_SLV_ID_W +
                                                     $clog2(AP_AXI_PERIPH_INGRESS_PORTS);
  localparam int unsigned AP_AXI_PERIPH_MAX_OUTSTANDING = 8;

  localparam int unsigned AP_AXI_PERIPH_EGRESS_APB   = 0;
  localparam int unsigned AP_AXI_PERIPH_EGRESS_FLASH = 1;

  // The AP physical map uses standard CLINT/PLIC locations and keeps every
  // independently decoded aperture disjoint.  The 4 MiB PLIC window includes
  // the M and S context register pages at offsets 0x0020_0000/0x0020_1000.
  localparam logic [AP_PADDR_W-1:0] AP_BOOT_ROM_BASE  = 48'h0000_0000_0000;
  localparam logic [AP_PADDR_W-1:0] AP_BOOT_ROM_LIMIT = 48'h0000_0001_0000;
  localparam logic [AP_PADDR_W-1:0] AP_CLINT_BASE     = 48'h0000_0200_0000;
  localparam logic [AP_PADDR_W-1:0] AP_CLINT_LIMIT    = 48'h0000_0201_0000;
  localparam logic [AP_PADDR_W-1:0] AP_PLIC_BASE      = 48'h0000_0c00_0000;
  localparam logic [AP_PADDR_W-1:0] AP_PLIC_LIMIT     = 48'h0000_0c40_0000;
  localparam logic [AP_PADDR_W-1:0] AP_APB_BASE       = 48'h0000_1000_0000;
  localparam logic [AP_PADDR_W-1:0] AP_APB_LIMIT      = 48'h0000_1100_0000;
  localparam logic [AP_PADDR_W-1:0] AP_BPI_BASE       = 48'h0000_2000_0000;
  localparam logic [AP_PADDR_W-1:0] AP_BPI_LIMIT      = 48'h0000_2800_0000;
  localparam logic [AP_PADDR_W-1:0] AP_DDR_BASE       = 48'h0000_8000_0000;
  localparam logic [AP_PADDR_W-1:0] AP_DDR_LIMIT      = 48'h0001_0000_0000;

  localparam logic [AP_PADDR_W-1:0] AP_UART0_BASE     = AP_APB_BASE + 48'h0000_0000;
  localparam logic [AP_PADDR_W-1:0] AP_SPI0_BASE      = AP_APB_BASE + 48'h0000_1000;
  localparam logic [AP_PADDR_W-1:0] AP_TIMER0_BASE    = AP_APB_BASE + 48'h0000_2000;
  localparam logic [AP_PADDR_W-1:0] AP_GPIO0_BASE     = AP_APB_BASE + 48'h0000_3000;
  localparam logic [AP_PADDR_W-1:0] AP_WDT0_BASE      = AP_APB_BASE + 48'h0000_4000;
  localparam logic [AP_PADDR_W-1:0] AP_ETH0_BASE      = AP_APB_BASE + 48'h0000_5000;
  localparam logic [AP_PADDR_W-1:0] AP_APB_PERIPH_SIZE= 48'h0000_1000;

  // The boot flash is a 128 MiB asynchronous x16 BPI NOR. BPI addresses
  // 16-bit words, while AP_BPI_BASE/LIMIT remain byte addresses.
  localparam int unsigned AP_BPI_DATA_W = 16;
  localparam int unsigned AP_BPI_ADDR_W = 26;
  localparam int unsigned AP_BPI_READ_WAIT_CYCLES = 1;

  function automatic logic ap_addr_in_range(
    input logic [AP_PADDR_W-1:0] addr,
    input logic [AP_PADDR_W-1:0] base,
    input logic [AP_PADDR_W-1:0] limit
  );
    return (addr >= base) && (addr < limit);
  endfunction

  function automatic logic ap_is_ddr_addr(input logic [AP_PADDR_W-1:0] addr);
    return ap_addr_in_range(addr, AP_DDR_BASE, AP_DDR_LIMIT);
  endfunction

endpackage
