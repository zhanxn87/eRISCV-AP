// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

// eRISCV-AP delivery SoC: RV64GC core + legacy 32-bit peripheral fabric + JTAG debug.
//
// Incrementally built on edu-rv32i-soc/rtl/soc/riscv_soc.sv.
// riscv_wrapper.sv (rtl/riscv_core/) is for standalone core verification only.
/* verilator lint_off WIDTHTRUNC */
import soc_pkg::*;

module soc #(
  parameter bit ENABLE_LMEM_EARLY_LOAD_P      = 1'b1,
  parameter bit ENABLE_LOAD_RESPONSE_BYPASS_P = 1'b1,
  parameter bit ENABLE_BHT_P                  = 1'b1,
  parameter bit ENABLE_RAS_P                  = 1'b1,
  parameter bit ENABLE_UPPER_32_PREFETCH_P    = 1'b1,
  parameter int unsigned MUL_ITER_BITS_P      = 16,
  parameter bit SYS_SRAM_LOAD_BYPASS_P        = 1'b0
) (
  // Root clock/reset and fetch startup
  input  logic        clk,
  input  logic        rst_n,
  input  logic        ext_rst_n_i,
  input  logic        fetch_enable_i,

  // Boot-mode selection and UART boot pins
  input  logic [2:0]  boot_mode_i,
  input  logic        boot_uart_rx_i,
  output logic        boot_uart_overrun_o,
  output logic        boot_uart_protocol_error_o,
  input  logic [63:0] boot_addr_i,

  // UART, GPIO, and SPI peripheral pins
  input  logic        uart_rx_i,
  output logic        uart_tx_o,
  input  logic [31:0] gpio_i,
  output logic [31:0] gpio_o,
  output logic [31:0] gpio_oe_o,
  output logic        spi_sclk_o,
  output logic        spi_mosi_o,
  input  logic        spi_miso_i,
  output logic [3:0]  spi_ss_o,

  // JTAG debug pins
  input  logic        jtag_tck_i,
  input  logic        jtag_tms_i,
  input  logic        jtag_tdi_i,
  output logic        jtag_tdo_o,
  input  logic        jtag_trst_n_i,

  // External PLIC interrupt inputs
  input  logic [PLIC_EXT_IRQ_COUNT-1:0] ext_irq_i
);

  // Product contract: both local memories acknowledge accepted requests after
  // one cycle.  Latency variation belongs in standalone DV wrappers, not the
  // MCU integration interface.
  localparam int IMEM_READ_LATENCY = 1;
  localparam int DMEM_READ_LATENCY = 1;

  // =========================================================================
  // Core / bus / peripheral wires
  // =========================================================================
  logic        imem_req, imem_ready, imem_rvalid;
  logic [47:0] imem_addr;
  logic [31:0] imem_rdata;
  logic        imem_legacy_req, imem_legacy_ready, imem_legacy_rvalid;
  logic [31:0] imem_legacy_addr, imem_legacy_rdata;
  logic        data_req, data_we;
  logic [47:0] data_addr;
  logic [63:0] data_wdata;
  logic [7:0]  data_be;
  logic        data_resp_valid;
  logic [63:0] data_rdata;
  logic        data_err;
  // 32-bit legacy fabric side of the RV64 D-bus boundary.
  logic        data32_req, data32_we, data32_resp_valid, data32_err;
  logic [3:0]  data32_be;
  logic [31:0] data32_addr, data32_wdata, data32_rdata;
  // EX-stage local-memory read candidate and completion
  logic        lmem_req, lmem_accept, lmem_resp_valid, lmem_err;
  logic [47:0] lmem_addr;
  logic [63:0] lmem_rdata;
  logic        lmem_dmem_candidate, lmem32_req, lmem32_accept;
  logic        lmem32_resp_valid, lmem32_err;
  logic [31:0] lmem32_addr, lmem32_rdata;
  // DBus executable-IMEM transaction
  logic        imem_dbus_req, imem_dbus_we, imem_dbus_resp_valid, imem_dbus_err;
  logic [3:0]  imem_dbus_be;
  logic [31:0] imem_dbus_addr, imem_dbus_wdata, imem_dbus_rdata;
  // DBus DTCM transaction and physical SRAM port
  logic        mem_req, mem_we, mem_resp_valid, mem_err, mem_write_accept;
  logic [3:0]  mem_be;
  logic [31:0] mem_addr, mem_wdata, mem_rdata;
  logic        system_sram_cpu_req, system_sram_cpu_we, system_sram_cpu_ready;
  logic        system_sram_cpu_resp_valid, system_sram_cpu_err;
  logic [3:0]  system_sram_cpu_be;
  logic [31:0] system_sram_cpu_addr, system_sram_cpu_wdata, system_sram_cpu_rdata;
  logic        dma_cfg_req, dma_cfg_we, dma_cfg_resp_valid, dma_cfg_err, dma_irq;
  logic [31:0] dma_cfg_addr, dma_cfg_wdata, dma_cfg_rdata;
  logic        dma_mem_req, dma_mem_we, dma_mem_ready, dma_mem_resp_valid, dma_mem_err;
  logic [3:0]  dma_mem_be;
  logic [31:0] dma_mem_addr, dma_mem_wdata, dma_mem_rdata;
  logic        dma_uart_tx_valid, dma_uart_tx_ready;
  logic [7:0]  dma_uart_tx_data;
  logic        dmem_req, dmem_we, dmem_resp_valid, dmem_resp_write, dmem_err;
  logic [3:0]  dmem_be;
  logic [31:0] dmem_addr_bus, dmem_wdata, dmem_rdata;
  // Debug system-bus access and DTCM arbitration
  logic        sba_req, sba_we, sba_resp_valid, sba_err;
  logic [3:0]  sba_be;
  logic [31:0] sba_addr, sba_wdata, sba_rdata;
  logic        dmem_sba_req;
  // DBus-to-APB bridge transaction
  logic        apb_req, apb_we, apb_resp_valid, apb_err;
  logic [3:0]  apb_be;
  logic [31:0] apb_addr, apb_wdata, apb_rdata;
  logic        psel, penable, pwrite, pready, pslverr;
  logic [31:0] paddr, pwdata, prdata;
  logic [3:0]  pstrb;
  // APB peripheral selects, responses, and IRQs
  logic        uart_psel, uart_pready, uart_pslverr, uart_irq, uart_busy;
  logic [31:0] uart_prdata;
  logic        gpio_psel, gpio_pready, gpio_pslverr;
  logic [31:0] gpio_prdata;
  logic        timer_psel, timer_pready, timer_pslverr, timer_irq, timer_busy;
  logic [31:0] timer_prdata;
  logic        spi_psel, spi_pready, spi_pslverr, spi_irq, spi_busy;
  logic [31:0] spi_prdata;
  logic        wdt_psel, wdt_pready, wdt_pslverr, wdt_irq, wdt_rst_n;
  logic        wdt_enabled, wdt_locked;
  logic [31:0] wdt_prdata;
  logic        clk_rst_psel, clk_rst_pready, clk_rst_pslverr;
  logic [31:0] clk_rst_prdata;
  // Clock/reset control and hart interrupt aggregation
  logic        sys_rst_req_n, sys_rst_n, core_rst_n;
  logic        cpu_wake, core_wfi_sleep, core_clk_en, core_clk;
  logic [4:0]  peri_clk_en, peri_rst_req_n, peri_rst_n, peri_clk;
  logic [31:0] core_irq;
  // PLIC and CLINT DBus transactions
  logic        plic_req, plic_we, plic_resp_valid, plic_write_accept, plic_err;
  logic [3:0]  plic_be;
  logic [31:0] plic_addr, plic_wdata, plic_rdata;
  logic [PLIC_NUM_SOURCES-1:0] plic_sources;
  (* ASYNC_REG = "TRUE" *) logic [PLIC_EXT_IRQ_COUNT-1:0] ext_irq_meta_q;
  (* ASYNC_REG = "TRUE" *) logic [PLIC_EXT_IRQ_COUNT-1:0] ext_irq_sync_q;
  logic        clint_req, clint_we, clint_resp_valid, clint_write_accept, clint_err;
  logic [3:0]  clint_be;
  logic [31:0] clint_addr, clint_wdata, clint_rdata;
  logic        clint_msip, clint_mtip;
  // Hart Debug control and abstract-register access
  logic        debug_halt_req, debug_resume_req, debug_halted, debug_running;
  logic [63:0] debug_pc;
  logic [2:0]  debug_cause;
  logic        debug_reg_req_valid;
  logic        debug_reg_write;
  logic [15:0] debug_reg_addr;
  logic [63:0] debug_reg_wdata;
  logic [63:0] debug_reg_rdata;
  logic        debug_reg_error;
  // Debug-controlled IMEM boot port and fetch release
  logic        debug_imem_boot_we;
  logic [soc_pkg::IMEM_WORD_ADDR_WIDTH-1:0] debug_imem_boot_addr;
  logic [31:0] debug_imem_boot_wdata;
  logic [3:0]  debug_imem_boot_be;
  logic        debug_boot_fetch_enable;
  logic        imem_boot_we;
  logic [soc_pkg::IMEM_WORD_ADDR_WIDTH-1:0] imem_boot_addr;
  logic [31:0] imem_boot_wdata;
  logic [3:0]  imem_boot_be;
  logic        core_fetch_enable;

  // =========================================================================
  // PLIC
  // =========================================================================
  logic        plic_meip;
  logic        plic_meip_q;
  logic [63:0] clint_mtime;
  // External PLIC sources are level-sensitive and may be asynchronous to the
  // root clock. Source IDs 1..16 are reserved for integrated peripherals;
  // ext_irq_i[0] maps to PLIC source 17. M2 ties the DMA/device slots 5..16
  // low while preserving the common family PLIC source ABI.
  always_ff @(posedge clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      ext_irq_meta_q <= '0;
      ext_irq_sync_q <= '0;
    end else begin
      ext_irq_meta_q <= ext_irq_i;
      ext_irq_sync_q <= ext_irq_meta_q;
    end
  end

  always_comb begin
    plic_sources = '0;
    plic_sources[PLIC_SRC_UART - 1] = uart_irq;
    plic_sources[PLIC_SRC_TIMER - 1] = timer_irq;
    plic_sources[PLIC_SRC_SPI - 1] = spi_irq;
    plic_sources[PLIC_SRC_WDT - 1] = wdt_irq;
    plic_sources[PLIC_SRC_DMA - 1] = dma_irq;
    plic_sources[PLIC_EXT_IRQ_FIRST - 1 +: PLIC_EXT_IRQ_COUNT] = ext_irq_sync_q;
  end

  // The hart only sees architectural machine interrupt pending bits. PLIC
  // owns MEIP; CLINT owns MTIP and MSIP. No external source bypasses them.
  always_comb begin
    core_irq = '0;
    // Register the PLIC level before it enters the core. This prevents the
    // 32-source priority encoder from sharing the core redirect/IMEM path.
    core_irq[11] = plic_meip_q;
    core_irq[7] = clint_mtip;
    core_irq[3] = clint_msip;
  end

  always_ff @(posedge clk or negedge sys_rst_n) begin
    if (!sys_rst_n)
      plic_meip_q <= 1'b0;
    else
      plic_meip_q <= plic_meip;
  end
  assign imem_boot_we    = debug_imem_boot_we;
  assign imem_boot_addr  = debug_imem_boot_addr;
  assign imem_boot_wdata = debug_imem_boot_wdata;
  assign imem_boot_be    = debug_imem_boot_be;
  assign core_fetch_enable = fetch_enable_i & debug_boot_fetch_enable;

  clock_gate core_clock_gate_i (
    .clk_i   (clk),
    .en_i    (core_clk_en),
    .clk_o   (core_clk)
  );

  reset_sync sys_reset_sync_i (
    .clk_i    (clk),
    .arst_n_i (sys_rst_req_n),
    .srst_n_o (sys_rst_n)
  );

  reset_sync core_reset_sync_i (
    .clk_i    (core_clk),
    .arst_n_i (sys_rst_n),
    .srst_n_o (core_rst_n)
  );

  for (genvar clock_index = 0; clock_index < 5; clock_index++) begin : gen_peri_clock_gate
    clock_gate peripheral_clock_gate_i (
      .clk_i   (clk),
      .en_i    (peri_clk_en[clock_index]),
      .clk_o   (peri_clk[clock_index])
    );
    reset_sync peripheral_reset_sync_i (
      .clk_i    (peri_clk[clock_index]),
      .arst_n_i (peri_rst_req_n[clock_index]),
      .srst_n_o (peri_rst_n[clock_index])
    );
  end

  // =========================================================================
  // RV64GC core
  // =========================================================================
  riscv_core #(
    .RESET_VECTOR_ADDR_P          (soc_pkg::IMEM_BASE_ADDR + 32'h0000_0080),
    .DEBUG_BASE_ADDR_P            (soc_pkg::IMEM_BASE_ADDR + 32'h0000_0100),
    .ENABLE_LMEM_EARLY_LOAD_P     (ENABLE_LMEM_EARLY_LOAD_P),
    .ENABLE_LOAD_RESPONSE_BYPASS_P(ENABLE_LOAD_RESPONSE_BYPASS_P),
    .ENABLE_BHT_P                 (ENABLE_BHT_P),
    .ENABLE_RAS_P                 (ENABLE_RAS_P),
    .ENABLE_UPPER_32_PREFETCH_P   (ENABLE_UPPER_32_PREFETCH_P),
    .MUL_ITER_BITS_P               (MUL_ITER_BITS_P)
  ) riscv_core_i (
    // Clock/reset and fetch startup
    .clk                 (core_clk),
    .rst_n               (core_rst_n),
    .fetch_enable_i      (core_fetch_enable),
    .boot_addr_i         (boot_addr_i),
    // Debug control and abstract register access
    .debug_halt_req_i    (debug_halt_req),
    .debug_resume_req_i  (debug_resume_req),
    .debug_halted_o      (debug_halted),
    .debug_running_o     (debug_running),
    .debug_pc_o          (debug_pc),
    .debug_cause_o       (debug_cause),
    .debug_reg_req_valid_i(debug_reg_req_valid),
    .debug_reg_write_i   (debug_reg_write),
    .debug_reg_addr_i    (debug_reg_addr),
    .debug_reg_wdata_i   (debug_reg_wdata),
    .debug_reg_rdata_o   (debug_reg_rdata),
    .debug_reg_error_o   (debug_reg_error),
    // Instruction-memory transaction
    .imem_req_o          (imem_req),
    .imem_ready_i        (imem_ready),
    .imem_addr_o         (imem_addr),
    .imem_rvalid_i       (imem_rvalid),
    .imem_rdata_i        (imem_rdata),
    // Data-memory transaction
    .data_req_o          (data_req),
    .data_addr_o         (data_addr),
    .data_wdata_o        (data_wdata),
    .data_we_o           (data_we),
    .data_be_o           (data_be),
    .data_resp_valid_i   (data_resp_valid),
    .data_rdata_i        (data_rdata),
    .data_err_i          (data_err),
    // Optional local-memory read transaction
    .lmem_req_o          (lmem_req),
    .lmem_addr_o         (lmem_addr),
    .lmem_accept_i       (lmem_accept),
    .lmem_resp_valid_i   (lmem_resp_valid),
    .lmem_rdata_i        (lmem_rdata),
    .lmem_err_i          (lmem_err),
    // Time, interrupt, and WFI wake inputs
    .mtime_i             (clint_mtime),
    .irq_i               (core_irq),
    .wfi_wake_i          (cpu_wake),
    .wfi_sleep_o         (core_wfi_sleep)
  );

  // =========================================================================
  // IMEM
  // =========================================================================
  ibus48_to_ibus32_adapter ibus_width_adapter_i (
    .clk             (clk),
    .rst_n           (sys_rst_n),
    .imem_req_i      (imem_req),
    .imem_addr_i     (imem_addr),
    .imem_ready_o    (imem_ready),
    .imem_rvalid_o   (imem_rvalid),
    .imem_rdata_o    (imem_rdata),
    .legacy_req_o    (imem_legacy_req),
    .legacy_addr_o   (imem_legacy_addr),
    .legacy_ready_i  (imem_legacy_ready),
    .legacy_rvalid_i (imem_legacy_rvalid),
    .legacy_rdata_i  (imem_legacy_rdata)
  );

  instr_mem #(
    .ADDR_WIDTH  (soc_pkg::IMEM_WORD_ADDR_WIDTH),
    .READ_LATENCY(IMEM_READ_LATENCY)
  ) instr_mem_i (
    // Clock/reset
    .clk              (clk),
    .rst_n            (sys_rst_n),
    // Core instruction fetch port
    .rd_req_i         (imem_legacy_req),
    .ready_o          (imem_legacy_ready),
    .addr_i           (imem_legacy_addr[soc_pkg::IMEM_WORD_ADDR_WIDTH+1:2]),
    .rvalid_o         (imem_legacy_rvalid),
    .instr_o          (imem_legacy_rdata),
    // Debug/boot write port
    .boot_we_i        (imem_boot_we),
    .boot_addr_i      (imem_boot_addr),
    .boot_wdata_i     (imem_boot_wdata),
    .boot_be_i        (imem_boot_be),
    // Core D-bus executable-IMEM port
    .data_req_i       (imem_dbus_req),
    .data_we_i        (imem_dbus_we),
    .data_be_i        (imem_dbus_be),
    .data_addr_i      (imem_dbus_addr[soc_pkg::IMEM_WORD_ADDR_WIDTH+1:2]),
    .data_wdata_i     (imem_dbus_wdata),
    .data_resp_valid_o(imem_dbus_resp_valid),
    .data_rdata_o     (imem_dbus_rdata),
    .data_err_o       (imem_dbus_err)
  );

  // =========================================================================
  // DBus interconnect → DMEM | PLIC | APB
  // =========================================================================
  dbus64_to_dbus32_adapter dbus_width_adapter_i (
    .clk                (clk),
    .rst_n              (sys_rst_n),
    .dbus_req_i         (data_req),
    .dbus_addr_i        (data_addr),
    .dbus_wdata_i       (data_wdata),
    .dbus_we_i          (data_we),
    .dbus_be_i          (data_be),
    .dbus_resp_valid_o  (data_resp_valid),
    .dbus_rdata_o       (data_rdata),
    .dbus_err_o         (data_err),
    .legacy_req_o       (data32_req),
    .legacy_addr_o      (data32_addr),
    .legacy_wdata_o     (data32_wdata),
    .legacy_we_o        (data32_we),
    .legacy_be_o        (data32_be),
    .legacy_resp_valid_i(data32_resp_valid),
    .legacy_rdata_i     (data32_rdata),
    .legacy_err_i       (data32_err)
  );

  dbus_interconnect dbus_interconnect_i (
    // Clock/reset for delayed-response target tracking
    .clk              (clk),
    .rst_n            (sys_rst_n),
    // Core D-bus request and response
    .dbus_req_i       (data32_req),
    .dbus_addr_i      (data32_addr),
    .dbus_wdata_i     (data32_wdata),
    .dbus_we_i        (data32_we),
    .dbus_be_i        (data32_be),
    .dbus_resp_valid_o(data32_resp_valid),
    .dbus_rdata_o     (data32_rdata),
    .dbus_err_o       (data32_err),
    // Executable IMEM target
    .imem_req_o       (imem_dbus_req),
    .imem_we_o        (imem_dbus_we),
    .imem_be_o        (imem_dbus_be),
    .imem_addr_o      (imem_dbus_addr),
    .imem_wdata_o     (imem_dbus_wdata),
    .imem_resp_valid_i(imem_dbus_resp_valid),
    .imem_rdata_i     (imem_dbus_rdata),
    .imem_err_i       (imem_dbus_err),
    // DTCM target
    .mem_req_o        (mem_req),
    .mem_we_o         (mem_we),
    .mem_be_o         (mem_be),
    .mem_addr_o       (mem_addr),
    .mem_wdata_o      (mem_wdata),
    .mem_resp_valid_i (mem_resp_valid),
    .mem_rdata_i      (mem_rdata),
    .mem_err_i        (mem_err),
    .mem_write_accept_i(mem_write_accept),
    .system_sram_req_o(system_sram_cpu_req),
    .system_sram_we_o (system_sram_cpu_we),
    .system_sram_be_o (system_sram_cpu_be),
    .system_sram_addr_o(system_sram_cpu_addr),
    .system_sram_wdata_o(system_sram_cpu_wdata),
    .system_sram_resp_valid_i(system_sram_cpu_resp_valid),
    .system_sram_rdata_i(system_sram_cpu_rdata),
    .system_sram_err_i(system_sram_cpu_err),
    .dma_req_o        (dma_cfg_req),
    .dma_we_o         (dma_cfg_we),
    .dma_addr_o       (dma_cfg_addr),
    .dma_wdata_o      (dma_cfg_wdata),
    .dma_resp_valid_i (dma_cfg_resp_valid),
    .dma_rdata_i      (dma_cfg_rdata),
    .dma_err_i        (dma_cfg_err),
    // APB target
    .apb_req_o        (apb_req),
    .apb_we_o         (apb_we),
    .apb_be_o         (apb_be),
    .apb_addr_o       (apb_addr),
    .apb_wdata_o      (apb_wdata),
    .apb_resp_valid_i (apb_resp_valid),
    .apb_rdata_i      (apb_rdata),
    .apb_err_i        (apb_err),
    // PLIC target
    .plic_req_o       (plic_req),
    .plic_we_o        (plic_we),
    .plic_be_o        (plic_be),
    .plic_addr_o      (plic_addr),
    .plic_wdata_o     (plic_wdata),
    .plic_resp_valid_i(plic_resp_valid),
    .plic_rdata_i     (plic_rdata),
    .plic_err_i       (plic_err),
    .plic_write_accept_i(plic_write_accept),
    // CLINT target
    .clint_req_o      (clint_req),
    .clint_we_o       (clint_we),
    .clint_be_o       (clint_be),
    .clint_addr_o     (clint_addr),
    .clint_wdata_o    (clint_wdata),
    .clint_resp_valid_i(clint_resp_valid),
    .clint_rdata_i    (clint_rdata),
    .clint_err_i      (clint_err),
    .clint_write_accept_i(clint_write_accept)
  );

  // =========================================================================
  // DMEM
  // =========================================================================
  logic [soc_pkg::DMEM_WORD_ADDR_WIDTH-1:0] dmem_addr;
  assign dmem_sba_req = sba_req && soc_pkg::is_dmem_addr(sba_addr);
  // Only the existing low-4-GiB DTCM aperture may accept an early load. All
  // other physical addresses fall back to the normal D-bus and are checked by
  // the 48-bit boundary adapter.
  assign lmem_dmem_candidate = lmem_req && !|lmem_addr[47:32] &&
                               soc_pkg::is_dmem_addr(lmem_addr[31:0]);
  assign dmem_addr = dmem_addr_bus[soc_pkg::DMEM_WORD_ADDR_WIDTH+1:2];

  lmem64_to_lmem32_adapter lmem_width_adapter_i (
    .clk                (clk),
    .rst_n              (sys_rst_n),
    .lmem_req_i         (lmem_dmem_candidate),
    .lmem_addr_i        (lmem_addr),
    .lmem_accept_o      (lmem_accept),
    .lmem_resp_valid_o  (lmem_resp_valid),
    .lmem_rdata_o       (lmem_rdata),
    .lmem_err_o         (lmem_err),
    .legacy_req_o       (lmem32_req),
    .legacy_addr_o      (lmem32_addr),
    .legacy_accept_i    (lmem32_accept),
    .legacy_resp_valid_i(lmem32_resp_valid),
    .legacy_rdata_i     (lmem32_rdata),
    .legacy_err_i       (lmem32_err)
  );

  data_mem_arbiter data_mem_arbiter_i (
    // Clock/reset
    .clk              (clk),
    .rst_n            (sys_rst_n),
    // Debug SBA request
    .sba_req_i        (sba_req),
    .sba_dmem_req_i   (dmem_sba_req),
    .sba_we_i         (sba_we),
    .sba_be_i         (sba_be),
    .sba_addr_i       (sba_addr),
    .sba_wdata_i      (sba_wdata),
    .sba_resp_valid_o (sba_resp_valid),
    .sba_rdata_o      (sba_rdata),
    .sba_err_o        (sba_err),
    // Core DTCM request and response
    .mem_req_i        (mem_req),
    .mem_we_i         (mem_we),
    .mem_be_i         (mem_be),
    .mem_addr_i       (mem_addr),
    .mem_wdata_i      (mem_wdata),
    .mem_write_accept_o(mem_write_accept),
    .mem_resp_valid_o (mem_resp_valid),
    .mem_rdata_o      (mem_rdata),
    .mem_err_o        (mem_err),
    // EX-stage local-memory read transaction
    .lmem_req_i       (lmem32_req),
    .lmem_addr_i      (lmem32_addr),
    .lmem_accept_o    (lmem32_accept),
    .lmem_resp_valid_o(lmem32_resp_valid),
    .lmem_rdata_o     (lmem32_rdata),
    .lmem_err_o       (lmem32_err),
    // Physical DTCM port
    .dmem_req_o       (dmem_req),
    .dmem_we_o        (dmem_we),
    .dmem_be_o        (dmem_be),
    .dmem_addr_o      (dmem_addr_bus),
    .dmem_wdata_o     (dmem_wdata),
    .dmem_resp_valid_i(dmem_resp_valid),
    .dmem_resp_write_i(dmem_resp_write),
    .dmem_rdata_i     (dmem_rdata),
    .dmem_err_i       (dmem_err)
  );

  data_mem #(
    .ADDR_WIDTH  (soc_pkg::DMEM_WORD_ADDR_WIDTH),
    .READ_LATENCY(DMEM_READ_LATENCY)
  ) data_mem_i (
    // Clock/reset
    .clk          (clk),
    .rst_n        (sys_rst_n),
    // Physical DTCM port
    .req_i        (dmem_req),
    .we_i         (dmem_we),
    .be_i         (dmem_be),
    .addr_i       (dmem_addr),
    .wdata_i      (dmem_wdata),
    .resp_valid_o (dmem_resp_valid),
    .resp_write_o (dmem_resp_write),
    .rdata_o      (dmem_rdata),
    .err_o        (dmem_err)
  );

  // =========================================================================
  // System SRAM + DMA
  // =========================================================================
  system_sram_fabric #(
    .SYS_SRAM_LOAD_BYPASS_P(SYS_SRAM_LOAD_BYPASS_P)
  ) system_sram_fabric_i (
    .clk              (clk),
    .rst_n            (sys_rst_n),
    .cpu_req_valid_i  (system_sram_cpu_req),
    .cpu_req_we_i     (system_sram_cpu_we),
    .cpu_req_be_i     (system_sram_cpu_be),
    .cpu_req_addr_i   (system_sram_cpu_addr),
    .cpu_req_wdata_i  (system_sram_cpu_wdata),
    .cpu_req_ready_o  (system_sram_cpu_ready),
    .cpu_resp_valid_o (system_sram_cpu_resp_valid),
    .cpu_resp_rdata_o (system_sram_cpu_rdata),
    .cpu_resp_err_o   (system_sram_cpu_err),
    .dma_req_valid_i  (dma_mem_req),
    .dma_req_we_i     (dma_mem_we),
    .dma_req_be_i     (dma_mem_be),
    .dma_req_addr_i   (dma_mem_addr),
    .dma_req_wdata_i  (dma_mem_wdata),
    .dma_req_ready_o  (dma_mem_ready),
    .dma_resp_valid_o (dma_mem_resp_valid),
    .dma_resp_rdata_o (dma_mem_rdata),
    .dma_resp_err_o   (dma_mem_err)
  );

  dma_controller dma_i (
    .clk              (clk),
    .rst_n            (sys_rst_n),
    .cfg_req_i        (dma_cfg_req),
    .cfg_we_i         (dma_cfg_we),
    .cfg_addr_i       (dma_cfg_addr),
    .cfg_wdata_i      (dma_cfg_wdata),
    .cfg_resp_valid_o (dma_cfg_resp_valid),
    .cfg_rdata_o      (dma_cfg_rdata),
    .cfg_err_o        (dma_cfg_err),
    .dma_req_valid_o  (dma_mem_req),
    .dma_req_we_o     (dma_mem_we),
    .dma_req_be_o     (dma_mem_be),
    .dma_req_addr_o   (dma_mem_addr),
    .dma_req_wdata_o  (dma_mem_wdata),
    .dma_req_ready_i  (dma_mem_ready),
    .dma_resp_valid_i (dma_mem_resp_valid),
    .dma_resp_rdata_i (dma_mem_rdata),
    .dma_resp_err_i   (dma_mem_err),
    .uart_tx_valid_o  (dma_uart_tx_valid),
    .uart_tx_data_o   (dma_uart_tx_data),
    .uart_tx_ready_i  (dma_uart_tx_ready),
    .irq_o            (dma_irq)
  );

  // =========================================================================
  // DBus → APB bridge
  // =========================================================================
  dbus_to_apb dbus_to_apb_i (
    // Clock/reset
    .clk                 (clk),
    .rst_n               (sys_rst_n),
    // DBus target request and response
    .dbus_req_i          (apb_req),
    .dbus_we_i           (apb_we),
    .dbus_be_i           (apb_be),
    .dbus_addr_i         (apb_addr),
    .dbus_wdata_i        (apb_wdata),
    .dbus_resp_valid_o   (apb_resp_valid),
    .dbus_rdata_o        (apb_rdata),
    .dbus_err_o          (apb_err),
    // APB master transaction
    .psel_o              (psel),
    .penable_o           (penable),
    .pwrite_o            (pwrite),
    .paddr_o             (paddr),
    .pwdata_o            (pwdata),
    .pstrb_o             (pstrb),
    // APB target response
    .pready_i            (pready),
    .prdata_i            (prdata),
    .pslverr_i           (pslverr)
  );

  // =========================================================================
  // APB interconnect → peripherals
  // =========================================================================
  apb_interconnect apb_interconnect_i (
    // APB master address phase
    .psel_i          (psel),
    .penable_i       (penable),
    .paddr_i         (paddr),
    // UART target
    .uart_psel_o     (uart_psel),
    .uart_pready_i   (uart_pready),
    .uart_prdata_i   (uart_prdata),
    .uart_pslverr_i  (uart_pslverr),
    // GPIO target
    .gpio_psel_o     (gpio_psel),
    .gpio_pready_i   (gpio_pready),
    .gpio_prdata_i   (gpio_prdata),
    .gpio_pslverr_i  (gpio_pslverr),
    // Timer target
    .timer_psel_o    (timer_psel),
    .timer_pready_i  (timer_pready),
    .timer_prdata_i  (timer_prdata),
    .timer_pslverr_i (timer_pslverr),
    // SPI target
    .spi_psel_o      (spi_psel),
    .spi_pready_i    (spi_pready),
    .spi_prdata_i    (spi_prdata),
    .spi_pslverr_i   (spi_pslverr),
    // Watchdog target
    .wdt_psel_o      (wdt_psel),
    .wdt_pready_i    (wdt_pready),
    .wdt_prdata_i    (wdt_prdata),
    .wdt_pslverr_i   (wdt_pslverr),
    // Clock/reset target
    .clk_rst_psel_o  (clk_rst_psel),
    .clk_rst_pready_i(clk_rst_pready),
    .clk_rst_prdata_i(clk_rst_prdata),
    .clk_rst_pslverr_i(clk_rst_pslverr),
    // Peripheral gating and consolidated APB response
    .peri_clk_en_i   (peri_clk_en),
    .peri_rst_n_i    (peri_rst_n),
    .pready_o        (pready),
    .prdata_o        (prdata),
    .pslverr_o       (pslverr)
  );

  // =========================================================================
  // APB Peripherals
  // =========================================================================
  clk_rst_ctrl clk_rst_ctrl_i (
    // Root clock/reset
    .clk_sys           (clk),
    .por_n_i           (rst_n),
    // APB slave transaction
    .psel_i            (clk_rst_psel),
    .penable_i         (penable),
    .pwrite_i          (pwrite),
    .paddr_i           (paddr),
    .pwdata_i          (pwdata),
    .pstrb_i           (pstrb),
    .pready_o          (clk_rst_pready),
    .prdata_o          (clk_rst_prdata),
    .pslverr_o         (clk_rst_pslverr),
    // Reset, wake, and activity inputs
    .ext_rst_n_i       (ext_rst_n_i),
    .wdt_rst_n_i       (wdt_rst_n),
    .wdt_pretimeout_i  (wdt_irq),
    .wdt_enabled_i     (wdt_enabled),
    .wdt_locked_i      (wdt_locked),
    .uart_rx_i         (uart_rx_i),
    .gpio_i            (gpio_i[GPIO_WIDTH-1:0]),
    .clint_mtip_i      (clint_mtip),
    .cpu_wfi_i         (core_wfi_sleep),
    .cpu_irq_pending_i (|core_irq),
    .debug_halt_req_i  (debug_halt_req),
    .peri_busy_i       ({2'b00, timer_busy, spi_busy, uart_busy | dma_uart_tx_valid}),
    // Generated reset and clock enables
    .cpu_wake_o        (cpu_wake),
    .core_clk_en_o     (core_clk_en),
    .peri_clk_en_o     (peri_clk_en),
    .peri_rst_n_o      (peri_rst_req_n),
    .sys_rst_n_o       (sys_rst_req_n)
  );

  uart_apb #(
    .TX_FIFO_DEPTH (soc_pkg::UART_TX_FIFO_DEPTH),
    .RX_FIFO_DEPTH (soc_pkg::UART_RX_FIFO_DEPTH)
  ) uart0_i (
    // Peripheral clock/reset and APB slave transaction
    .pclk      (peri_clk[0]),
    .presetn   (peri_rst_n[0]),
    .psel_i    (uart_psel),
    .penable_i (penable),
    .pwrite_i  (pwrite),
    .paddr_i   (paddr),
    .pwdata_i  (pwdata),
    .pstrb_i   (pstrb),
    .pready_o  (uart_pready),
    .prdata_o  (uart_prdata),
    .pslverr_o (uart_pslverr),
    .dma_tx_valid_i(dma_uart_tx_valid),
    .dma_tx_data_i (dma_uart_tx_data),
    .dma_tx_ready_o(dma_uart_tx_ready),
    // UART pins, IRQ, and activity
    .uart_rx_i (uart_rx_i),
    .uart_tx_o (uart_tx_o),
    .irq_o     (uart_irq),
    .busy_o    (uart_busy)
  );

  gpio_apb gpio0_i (
    // Peripheral clock/reset and APB slave transaction
    .pclk      (peri_clk[3]),
    .presetn   (peri_rst_n[3]),
    .psel_i    (gpio_psel),
    .penable_i (penable),
    .pwrite_i  (pwrite),
    .paddr_i   (paddr),
    .pwdata_i  (pwdata),
    .pstrb_i   (pstrb),
    .pready_o  (gpio_pready),
    .prdata_o  (gpio_prdata),
    .pslverr_o (gpio_pslverr),
    // GPIO pins
    .gpio_i    (gpio_i),
    .gpio_o    (gpio_o),
    .gpio_oe_o (gpio_oe_o)
  );

  timer_apb timer0_i (
    // Peripheral clock/reset and APB slave transaction
    .pclk      (peri_clk[2]),
    .presetn   (peri_rst_n[2]),
    .psel_i    (timer_psel),
    .penable_i (penable),
    .pwrite_i  (pwrite),
    .paddr_i   (paddr),
    .pwdata_i  (pwdata),
    .pstrb_i   (pstrb),
    .pready_o  (timer_pready),
    .prdata_o  (timer_prdata),
    .pslverr_o (timer_pslverr),
    // Timer IRQ and activity
    .irq_o     (timer_irq),
    .busy_o    (timer_busy)
  );

  spi_apb spi0_i (
    // Peripheral clock/reset and APB slave transaction
    .pclk      (peri_clk[1]),
    .presetn   (peri_rst_n[1]),
    .psel_i    (spi_psel),
    .penable_i (penable),
    .pwrite_i  (pwrite),
    .paddr_i   (paddr),
    .pwdata_i  (pwdata),
    .pstrb_i   (pstrb),
    .pready_o  (spi_pready),
    .prdata_o  (spi_prdata),
    .pslverr_o (spi_pslverr),
    // SPI pins, IRQ, and activity
    .spi_sclk_o(spi_sclk_o),
    .spi_mosi_o(spi_mosi_o),
    .spi_miso_i(spi_miso_i),
    .spi_ss_o  (spi_ss_o),
    .irq_o     (spi_irq),
    .busy_o    (spi_busy)
  );

  // =========================================================================
  // Watchdog Timer
  // =========================================================================
  watchdog_apb watchdog_i (
    // Peripheral clock/reset and APB slave transaction
    .pclk       (peri_clk[4]),
    .presetn    (peri_rst_n[4]),
    .psel_i     (wdt_psel),
    .penable_i  (penable),
    .pwrite_i   (pwrite),
    .paddr_i    (paddr),
    .pwdata_i   (pwdata),
    .pstrb_i    (pstrb),
    .pready_o   (wdt_pready),
    .prdata_o   (wdt_prdata),
    .pslverr_o  (wdt_pslverr),
    // Debug state and watchdog outputs
    .debug_halted_i (debug_halted),
    .irq_o      (wdt_irq),
    .enabled_o  (wdt_enabled),
    .locked_o   (wdt_locked),
    .wdt_rst_n_o(wdt_rst_n)
  );

  // =========================================================================
  // CLINT — MSIP, MTIMECMP, MTIME (D-bus)
  // =========================================================================
  clint #(
    .BASE_ADDR (CLINT_BASE)
  ) clint_i (
    // Clock/reset and DBus target
    .clk          (clk),
    .rst_n        (sys_rst_n),
    .req_i        (clint_req),
    .we_i         (clint_we),
    .be_i         (clint_be),
    .addr_i       (clint_addr),
    .wdata_i      (clint_wdata),
    .hit_o        (),
    .write_accept_o(clint_write_accept),
    .resp_valid_o (clint_resp_valid),
    .rdata_o      (clint_rdata),
    .err_o        (clint_err),
    // Hart interrupt and time outputs
    .msip_o       (clint_msip),
    .mtip_o       (clint_mtip),
    .mtime_o      (clint_mtime)
  );

  // =========================================================================
  // PLIC v1.0.0 — 32 sources, drives MEIP
  // =========================================================================
  plic #(
    .NUM_SOURCES   (PLIC_NUM_SOURCES),
    .PRIORITY_BITS (PLIC_PRIORITY_BITS),
    .BASE_ADDR     (PLIC_BASE)
  ) plic_i (
    // Clock/reset and DBus target
    .clk          (clk),
    .rst_n        (sys_rst_n),
    .req_i        (plic_req),
    .we_i         (plic_we),
    .be_i         (plic_be),
    .addr_i       (plic_addr),
    .wdata_i      (plic_wdata),
    .hit_o        (),
    .write_accept_o(plic_write_accept),
    .resp_valid_o (plic_resp_valid),
    .rdata_o      (plic_rdata),
    .err_o        (plic_err),
    // Interrupt sources and MEIP output
    .src_i        (plic_sources),
    .meip_o       (plic_meip)
  );

  // =========================================================================
  // System Control + JTAG Debug
  // =========================================================================
  sys_ctrl #(
    .IMEM_BOOT_ADDR_WIDTH(soc_pkg::IMEM_WORD_ADDR_WIDTH)
  ) system_ctrl_subsystem_i (
    // Root clock/reset and JTAG pins
    .clk                     (clk),
    .rst_n                   (rst_n),
    .jtag_tck_i              (jtag_tck_i),
    .jtag_tms_i              (jtag_tms_i),
    .jtag_tdi_i              (jtag_tdi_i),
    .jtag_tdo_o              (jtag_tdo_o),
    .jtag_trst_n_i           (jtag_trst_n_i),
    // Hart debug state and abstract-register access
    .hart_halt_req_o         (debug_halt_req),
    .hart_resume_req_o       (debug_resume_req),
    .hart_halted_i           (debug_halted),
    .hart_running_i          (debug_running),
    .hart_pc_i               (debug_pc),
    .hart_cause_i            (debug_cause),
    .debug_reg_req_valid_o   (debug_reg_req_valid),
    .debug_reg_write_o       (debug_reg_write),
    .debug_reg_addr_o        (debug_reg_addr),
    .debug_reg_wdata_o       (debug_reg_wdata),
    .debug_reg_rdata_i       (debug_reg_rdata),
    .debug_reg_error_i       (debug_reg_error),
    // Debug SBA transaction
    .sba_req_o               (sba_req),
    .sba_we_o                (sba_we),
    .sba_addr_o              (sba_addr),
    .sba_wdata_o             (sba_wdata),
    .sba_be_o                (sba_be),
    .sba_resp_valid_i        (sba_resp_valid),
    .sba_rdata_i             (sba_rdata),
    .sba_err_i               (sba_err),
    // IMEM boot-write port and fetch release
    .imem_boot_we_o          (debug_imem_boot_we),
    .imem_boot_addr_o        (debug_imem_boot_addr),
    .imem_boot_wdata_o       (debug_imem_boot_wdata),
    .imem_boot_be_o          (debug_imem_boot_be),
    .boot_fetch_enable_o     (debug_boot_fetch_enable),
    // Boot mode, UART boot input, and diagnostics
    .boot_mode_i             (boot_mode_i),
    .boot_uart_rx_i          (boot_uart_rx_i),
    .boot_uart_divisor_i     (soc_pkg::BOOT_UART_DIVISOR),
    .boot_uart_overrun_o     (boot_uart_overrun_o),
    .boot_uart_protocol_error_o(boot_uart_protocol_error_o)
  );

endmodule
