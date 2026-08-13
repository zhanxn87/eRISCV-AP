// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

package soc_pkg;

  // =========================================================================
  // Product configuration -- eRISCV-M2 v2.0 address-space contract
  // =========================================================================
  // The hart-side contract is RV64 with a 48-bit physical address. Existing
  // TCM/APB infrastructure remains a 32-bit implementation detail behind the
  // SoC boundary adapters until the cached AXI/DDR subsystem replaces it.
  localparam int CORE_DATA_WIDTH = 64;
  localparam int CORE_PADDR_WIDTH = 48;
  localparam int LEGACY_FABRIC_DATA_WIDTH = 32;
  localparam int unsigned SOC_HART_COUNT = 1;

  localparam bit HAS_UART0        = 1'b1;
  localparam bit HAS_GPIO0        = 1'b1;
  localparam bit HAS_TIMER0       = 1'b1;
  localparam bit HAS_SPI0         = 1'b1;
  localparam bit HAS_WDT0         = 1'b1;
  localparam bit HAS_CLK_RST_CTRL = 1'b1;
  localparam bit HAS_CLINT        = 1'b1;
  localparam bit HAS_PLIC         = 1'b1;
  localparam bit HAS_DEBUG_MODULE = 1'b1;

  localparam int IMEM_WORD_ADDR_WIDTH = 15; //128 KiB ITCM
  localparam int DMEM_WORD_ADDR_WIDTH = 15; //128 KiB DTCM
  localparam int SYSTEM_SRAM_WORD_ADDR_WIDTH = 17; //512 KiB System SRAM
  localparam int unsigned SYSTEM_SRAM_BANK_COUNT = 8;
  localparam int unsigned SYSTEM_SRAM_BANK_BITS = $clog2(SYSTEM_SRAM_BANK_COUNT);
  localparam int SYSTEM_SRAM_BANK_WORD_ADDR_WIDTH =
      SYSTEM_SRAM_WORD_ADDR_WIDTH - SYSTEM_SRAM_BANK_BITS;
  localparam logic [31:0] IMEM_SIZE_BYTES = 32'd4 << IMEM_WORD_ADDR_WIDTH;
  localparam logic [31:0] DMEM_SIZE_BYTES = 32'd4 << DMEM_WORD_ADDR_WIDTH;
  localparam logic [31:0] SYSTEM_SRAM_SIZE_BYTES = 32'd4 << SYSTEM_SRAM_WORD_ADDR_WIDTH;

  // Boot UART timing is a SoC integration constant, not a core-visible port.
  localparam logic [31:0] CLK_FREQ          = 32'd100000000;
  localparam logic [31:0] BOOT_UART_BAUD    = 32'd115200;
  localparam logic [31:0] BOOT_UART_DIVISOR = CLK_FREQ / BOOT_UART_BAUD;
  localparam int UART_TX_FIFO_DEPTH = 32;
  localparam int UART_RX_FIFO_DEPTH = 64;
  localparam int unsigned GPIO_WIDTH = 8;
  localparam int unsigned PLIC_PRIORITY_BITS = 3;

  // =========================================================================
  // Address map and peripheral topology
  // =========================================================================
  localparam logic [31:0] IMEM_BASE_ADDR  = 32'h1000_0000;
  localparam logic [31:0] IMEM_LIMIT_ADDR = IMEM_BASE_ADDR + IMEM_SIZE_BYTES;
  localparam logic [31:0] DMEM_BASE_ADDR  = 32'h1100_0000;
  localparam logic [31:0] DMEM_LIMIT_ADDR = DMEM_BASE_ADDR + DMEM_SIZE_BYTES;
  localparam logic [31:0] SYSTEM_SRAM_BASE_ADDR = 32'h8000_0000;
  localparam logic [31:0] SYSTEM_SRAM_LIMIT_ADDR = SYSTEM_SRAM_BASE_ADDR + SYSTEM_SRAM_SIZE_BYTES;
  localparam logic [31:0] DMA_BASE_ADDR = 32'h5000_0000;
  localparam logic [31:0] DMA_LIMIT_ADDR = DMA_BASE_ADDR + 32'h0001_0000;

  localparam logic [31:0] APB_BASE_ADDR  = 32'h4000_0000;
  localparam logic [31:0] APB_LIMIT_ADDR = APB_BASE_ADDR + 32'h0100_0000;

  localparam logic [31:0] PERIPH_MASK = 32'hFFFF_0000;
  localparam logic [31:0] UART0_BASE  = 32'h4000_0000;
  localparam logic [31:0] GPIO0_BASE  = 32'h4001_0000;
  localparam logic [31:0] TIMER0_BASE = 32'h4002_0000;
  localparam logic [31:0] SPI0_BASE   = 32'h4003_0000;
  localparam logic [31:0] WDT0_BASE   = 32'h4004_0000;
  localparam logic [31:0] CLK_RST_CTRL_BASE = 32'h4005_0000;
  localparam logic [31:0] PLIC_BASE    = 32'h0C00_0000;
  localparam logic [31:0] PLIC_LIMIT_ADDR = PLIC_BASE + 32'h0020_1000;
  localparam int unsigned PLIC_NUM_SOURCES      = 32;
  localparam int unsigned PLIC_SRC_UART         = 1;
  localparam int unsigned PLIC_SRC_TIMER        = 2;
  localparam int unsigned PLIC_SRC_SPI          = 3;
  localparam int unsigned PLIC_SRC_WDT          = 4;
  localparam int unsigned PLIC_SRC_DMA          = 5;
  localparam int unsigned PLIC_SRC_ETHERNET     = 6;
  localparam int unsigned PLIC_SRC_WIFI         = 7;
  localparam int unsigned PLIC_SRC_SDIO         = 8;
  localparam int unsigned PLIC_SRC_USB          = 9;
  localparam int unsigned PLIC_SRC_I2S          = 10;
  localparam int unsigned PLIC_SRC_CAMERA       = 11;
  localparam int unsigned PLIC_SRC_ADC_DAC      = 12;
  localparam int unsigned PLIC_SRC_ACCEL        = 13;
  localparam int unsigned PLIC_SRC_GPIO         = 14;
  localparam int unsigned PLIC_SRC_CANFD        = 15;
  localparam int unsigned PLIC_SRC_SOC_CTRL     = 16;
  localparam int unsigned PLIC_EXT_IRQ_FIRST    = 17;
  localparam int unsigned PLIC_EXT_IRQ_COUNT    =
      PLIC_NUM_SOURCES - PLIC_EXT_IRQ_FIRST + 1;
  localparam logic [31:0] CLINT_BASE   = 32'h0200_0000;
  localparam logic [31:0] CLINT_LIMIT  = CLINT_BASE + 32'h0000_C000;
  localparam logic [31:0] DMI_BASE     = 32'h1A00_0000;

  // =========================================================================
  // Address helpers
  // =========================================================================
  function automatic logic addr_in_range(
    input logic [31:0] addr,
    input logic [31:0] base,
    input logic [31:0] limit
  );
    return (addr >= base) && (addr < limit);
  endfunction

  function automatic logic is_imem_addr(input logic [31:0] addr);
    return addr_in_range(addr, IMEM_BASE_ADDR, IMEM_LIMIT_ADDR);
  endfunction

  function automatic logic is_dmem_addr(input logic [31:0] addr);
    return addr_in_range(addr, DMEM_BASE_ADDR, DMEM_LIMIT_ADDR);
  endfunction

  function automatic logic is_system_sram_addr(input logic [31:0] addr);
    return addr_in_range(addr, SYSTEM_SRAM_BASE_ADDR, SYSTEM_SRAM_LIMIT_ADDR);
  endfunction

  function automatic logic is_dma_addr(input logic [31:0] addr);
    return addr_in_range(addr, DMA_BASE_ADDR, DMA_LIMIT_ADDR);
  endfunction

  function automatic logic is_apb_addr(input logic [31:0] addr);
    return addr_in_range(addr, APB_BASE_ADDR, APB_LIMIT_ADDR);
  endfunction

  function automatic logic is_plic_addr(input logic [31:0] addr);
    return addr_in_range(addr, PLIC_BASE, PLIC_LIMIT_ADDR);
  endfunction

  function automatic logic is_clint_addr(input logic [31:0] addr);
    return addr_in_range(addr, CLINT_BASE, CLINT_LIMIT);
  endfunction

  function automatic logic [IMEM_WORD_ADDR_WIDTH-1:0] imem_word_addr(input logic [31:0] addr);
    logic [31:0] word_addr;
    word_addr = (addr - IMEM_BASE_ADDR) >> 2;
    return word_addr[IMEM_WORD_ADDR_WIDTH-1:0];
  endfunction

  function automatic logic [DMEM_WORD_ADDR_WIDTH-1:0] dmem_word_addr(input logic [31:0] addr);
    logic [31:0] word_addr;
    word_addr = (addr - DMEM_BASE_ADDR) >> 2;
    return word_addr[DMEM_WORD_ADDR_WIDTH-1:0];
  endfunction

  function automatic logic is_uart0_addr(input logic [31:0] addr);
    return (addr & PERIPH_MASK) == UART0_BASE;
  endfunction

  function automatic logic is_gpio0_addr(input logic [31:0] addr);
    return (addr & PERIPH_MASK) == GPIO0_BASE;
  endfunction

  function automatic logic is_timer0_addr(input logic [31:0] addr);
    return (addr & PERIPH_MASK) == TIMER0_BASE;
  endfunction

  function automatic logic is_spi0_addr(input logic [31:0] addr);
    return (addr & PERIPH_MASK) == SPI0_BASE;
  endfunction

  function automatic logic is_wdt0_addr(input logic [31:0] addr);
    return (addr & PERIPH_MASK) == WDT0_BASE;
  endfunction

  function automatic logic is_clk_rst_ctrl_addr(input logic [31:0] addr);
    return (addr & PERIPH_MASK) == CLK_RST_CTRL_BASE;
  endfunction

endpackage
