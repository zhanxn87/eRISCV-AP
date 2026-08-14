// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

`timescale 1ns/1ps

// eRISCV-M2 SoC testbench.
// Instantiates soc with all ports.  Supports the same plusargs-based
// oracle flow as the core TB (regs/signature), plus PLIC stimulus.
module soc_tb #(
  parameter time JTAG_TCK_PERIOD              = 100,
  // Simulation configuration knobs forwarded unchanged to the delivery SoC.
  // Use integer parameters because Verilator -G overrides are integer-valued.
  parameter int ENABLE_LMEM_EARLY_LOAD_P      = 1,
  parameter int ENABLE_LOAD_RESPONSE_BYPASS_P = 1,
  parameter int ENABLE_BHT_P                  = 1,
  parameter int ENABLE_RAS_P                  = 1,
  parameter int ENABLE_UPPER_32_PREFETCH_P    = 1,
  parameter int MUL_ITER_BITS_P               = 16,
  parameter int SYS_SRAM_LOAD_BYPASS_P        = 0
);

  localparam CLK_PERIOD = 10;
  localparam time JTAG_TCK_QUARTER_PERIOD = JTAG_TCK_PERIOD / 4;
  localparam int IMEM_WORD_ADDR_WIDTH = soc_pkg::IMEM_WORD_ADDR_WIDTH;
  localparam int DMEM_WORD_ADDR_WIDTH = soc_pkg::DMEM_WORD_ADDR_WIDTH;
  localparam int INSTR_MEM_DEPTH = 1 << IMEM_WORD_ADDR_WIDTH;
  localparam int DATA_MEM_DEPTH = 1 << DMEM_WORD_ADDR_WIDTH;
  localparam int BOOT_UART_QUEUE_DEPTH = 1024;
  localparam int BOOT_UART_DIVISOR = soc_pkg::BOOT_UART_DIVISOR;
  localparam int PLIC_EXT_IRQ_COUNT = soc_pkg::PLIC_EXT_IRQ_COUNT;
  localparam int PLIC_EXT_IRQ_FIRST = soc_pkg::PLIC_EXT_IRQ_FIRST;
  localparam logic [31:0] RV32I_NOP = 32'h0000_0013;
  localparam string TB_PHASE_NAME = "ERISCV_M2_SOC";

  // =========================================================================
  // Clocks, reset, stimulus control
  // =========================================================================
  logic        clk;
  logic        rst_n = 1'b1;
  logic        fetch_enable_i;
  logic [63:0] boot_addr = soc_pkg::IMEM_BASE_ADDR;
  logic [PLIC_EXT_IRQ_COUNT-1:0] ext_irq, ext_irq_legacy, ext_irq_agent;
  logic        plic_agent_active, plic_agent_done;

  initial clk = 1'b0;
  always #(CLK_PERIOD / 2) clk = ~clk;

  // =========================================================================
  // SoC external interface wires
  // =========================================================================
  logic [2:0]  boot_mode;
  logic        boot_uart_rx;
  logic        boot_uart_overrun, boot_uart_protocol_error;
  logic        uart_rx, uart_tx;
  logic [31:0] gpio_in, gpio_out, gpio_oe;
  logic        spi_sclk, spi_mosi, spi_miso;
  logic [3:0]  spi_ss;
  logic        jtag_tck, jtag_tms, jtag_tdi, jtag_tdo, jtag_trst_n;
  AXI_BUS #(
    .AXI_ADDR_WIDTH(ap_soc_pkg::AP_PADDR_W),
    .AXI_DATA_WIDTH(ap_soc_pkg::AP_AXI_DATA_W),
    .AXI_ID_WIDTH(ap_soc_pkg::AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(ap_soc_pkg::AP_AXI_USER_W)
  ) ddr_axi ();
  AXI_BUS #(
    .AXI_ADDR_WIDTH(ap_soc_pkg::AP_PADDR_W),
    .AXI_DATA_WIDTH(ap_soc_pkg::AP_AXI_DATA_W),
    .AXI_ID_WIDTH(ap_soc_pkg::AP_AXI_SLV_ID_W),
    .AXI_USER_WIDTH(ap_soc_pkg::AP_AXI_USER_W)
  ) periph_axi ();

  // =========================================================================
  // DUT
  // =========================================================================
  soc #(
    .ENABLE_LOAD_RESPONSE_BYPASS_P(ENABLE_LOAD_RESPONSE_BYPASS_P != 0),
    .ENABLE_BHT_P                 (ENABLE_BHT_P != 0),
    .ENABLE_RAS_P                 (ENABLE_RAS_P != 0),
    .ENABLE_UPPER_32_PREFETCH_P   (ENABLE_UPPER_32_PREFETCH_P != 0),
    .MUL_ITER_BITS_P              (MUL_ITER_BITS_P),
    .SYS_SRAM_LOAD_BYPASS_P       (SYS_SRAM_LOAD_BYPASS_P != 0)
  ) dut (
    .clk                        (clk),
    .rst_n                      (rst_n),
    .fetch_enable_i             (fetch_enable_i),
    .ext_rst_n_i                (1'b1),
    .boot_addr_i                (boot_addr),
    .boot_mode_i                (boot_mode),
    .boot_uart_rx_i             (boot_uart_rx),
    .boot_uart_overrun_o        (boot_uart_overrun),
    .boot_uart_protocol_error_o(boot_uart_protocol_error),
    .ext_irq_i                 (ext_irq),
    .uart_rx_i                 (uart_rx),
    .uart_tx_o                 (uart_tx),
    .gpio_i                    (gpio_in),
    .gpio_o                    (gpio_out),
    .gpio_oe_o                 (gpio_oe),
    .spi_sclk_o                (spi_sclk),
    .spi_mosi_o                (spi_mosi),
    .spi_miso_i                (spi_miso),
    .spi_ss_o                  (spi_ss),
    .jtag_tck_i                (jtag_tck),
    .jtag_tms_i                (jtag_tms),
    .jtag_tdi_i                (jtag_tdi),
    .jtag_tdo_o                (jtag_tdo),
    .jtag_trst_n_i             (jtag_trst_n),
    .ddr_axi_o                 (ddr_axi),
    .periph_axi_o              (periph_axi)
  );

  // The D-Cache reaches this verification-only DDR line memory through the
  // same central AXI fabric exposed by the AP SoC. No AP peripheral AXI
  // slave exists yet, so terminate that egress as a non-responsive boundary.
  axi4_line_mem #(
    .LINE_ADDR_W_P(12)
  ) ddr_line_mem_i (
    .clk                 (clk),
    .rst_n               (rst_n),
    .s_axi_awid_i        (ddr_axi.aw_id),
    .s_axi_awaddr_i      (ddr_axi.aw_addr),
    .s_axi_awlen_i       (ddr_axi.aw_len),
    .s_axi_awsize_i      (ddr_axi.aw_size),
    .s_axi_awburst_i     (ddr_axi.aw_burst),
    .s_axi_awcache_i     (ddr_axi.aw_cache),
    .s_axi_awvalid_i     (ddr_axi.aw_valid),
    .s_axi_awready_o     (ddr_axi.aw_ready),
    .s_axi_wdata_i       (ddr_axi.w_data),
    .s_axi_wstrb_i       (ddr_axi.w_strb),
    .s_axi_wlast_i       (ddr_axi.w_last),
    .s_axi_wvalid_i      (ddr_axi.w_valid),
    .s_axi_wready_o      (ddr_axi.w_ready),
    .s_axi_bid_o         (ddr_axi.b_id),
    .s_axi_bresp_o       (ddr_axi.b_resp),
    .s_axi_bvalid_o      (ddr_axi.b_valid),
    .s_axi_bready_i      (ddr_axi.b_ready),
    .s_axi_arid_i        (ddr_axi.ar_id),
    .s_axi_araddr_i      (ddr_axi.ar_addr),
    .s_axi_arlen_i       (ddr_axi.ar_len),
    .s_axi_arsize_i      (ddr_axi.ar_size),
    .s_axi_arburst_i     (ddr_axi.ar_burst),
    .s_axi_arcache_i     (ddr_axi.ar_cache),
    .s_axi_arvalid_i     (ddr_axi.ar_valid),
    .s_axi_arready_o     (ddr_axi.ar_ready),
    .s_axi_rid_o         (ddr_axi.r_id),
    .s_axi_rdata_o       (ddr_axi.r_data),
    .s_axi_rresp_o       (ddr_axi.r_resp),
    .s_axi_rlast_o       (ddr_axi.r_last),
    .s_axi_rvalid_o      (ddr_axi.r_valid),
    .s_axi_rready_i      (ddr_axi.r_ready)
  );

  assign periph_axi.aw_ready = 1'b0;
  assign periph_axi.w_ready = 1'b0;
  assign periph_axi.b_id = '0;
  assign periph_axi.b_resp = 2'b11;
  assign periph_axi.b_user = '0;
  assign periph_axi.b_valid = 1'b0;
  assign periph_axi.ar_ready = 1'b0;
  assign periph_axi.r_id = '0;
  assign periph_axi.r_data = '0;
  assign periph_axi.r_resp = 2'b11;
  assign periph_axi.r_last = 1'b0;
  assign periph_axi.r_user = '0;
  assign periph_axi.r_valid = 1'b0;

  // =========================================================================
  // Oracle / stimulus variables
  // =========================================================================
  string   tc_name;
  string   boot_mode_name;
  string   instr_mem_file, expected_regs_file, reference_output_file, jtag_boot_trace_file;
  string   data_mem_file, dump_file;
  int      max_cycles, sig_base, tohost_addr, report_words_base, report_words_count;
  longint unsigned boot_addr_arg;
  int      irq_start_cycle, irq_duration;
  int      plic_src_cycle, plic_src_id, plic_src_duration;
  int      completion_reg;
  logic [31:0] completion_value, expected_tohost_value, expected_tohost_mask;
  int      run_cycle;
  int      uart_baud_div, expected_uart_baud_div, uart_rx_start_cycle, expected_uart_tx_byte, uart_rx_byte;
  int      spi_miso_byte, expected_spi_tx_byte, spi_transfer_count, expected_bus_errors, observed_bus_errors;
  int      gpio_in_value, expected_gpio_out, expected_gpio_oe;
  string   expected_uart_tx_bytes;
  bit      has_expected_regs, has_reference_output, has_data_mem_file, has_report_words, has_jtag_boot_trace;
  bit      has_plic_timer_source_report, plic_timer_source_seen;
  logic    timer_irq_prev;
  bit      expect_low_power;
  bit      low_power_sleep_seen, low_power_timer_seen, low_power_clint_seen, low_power_wake_seen;
  bit      has_expected_uart_tx, has_expected_uart_tx_bytes, has_expected_uart_baud_div, has_uart_rx_byte, has_tohost;
  bit      has_expected_tohost_value, has_expected_tohost_mask;
  bit      has_spi_miso_byte, has_expected_spi_tx, spi_slave_done, has_expected_bus_errors;
  bit      has_expected_gpio_out, has_expected_gpio_oe;
  bit      has_completion, completion_seen;
  bit      perf_profile_en;
  event    async_io_start;
  bit      tohost_matched;
  logic [31:0] tohost_observed;
  bit      uart_tx_done, uart_rx_done;
  logic    debug_halted, debug_running;
  logic [63:0] debug_pc;
  logic [2:0]  debug_cause;
  logic [7:0]  boot_uart_queue [0:BOOT_UART_QUEUE_DEPTH-1];
  int unsigned boot_uart_wr_index;
  int unsigned boot_uart_rd_index;
  int unsigned boot_uart_bit_countdown;
  logic [7:0]  boot_uart_shift_byte;
  logic [3:0]  boot_uart_bit_index;
  logic        boot_uart_active;

  localparam logic [6:0] DMI_DATA0      = 7'h04;
  localparam logic [6:0] DMI_DATA1      = 7'h05;
  localparam logic [6:0] DMI_DMCONTROL  = 7'h10;
  localparam logic [6:0] DMI_DMSTATUS   = 7'h11;
  localparam logic [6:0] DMI_ABSTRACTCS = 7'h16;
  localparam logic [6:0] DMI_COMMAND    = 7'h17;
  localparam logic [6:0] DMI_SBCS       = 7'h38;
  localparam logic [6:0] DMI_SBADDRESS0 = 7'h39;
  localparam logic [6:0] DMI_SBDATA0    = 7'h3c;
  localparam logic [1:0] DMI_OP_NOP     = 2'b00;
  localparam logic [1:0] DMI_OP_READ    = 2'b01;
  localparam logic [1:0] DMI_OP_WRITE   = 2'b10;
  localparam logic [1:0] DMI_RESP_OK    = 2'b00;
  localparam logic [1:0] DMI_RESP_ERR   = 2'b10;
  localparam int JTAG_IR_WIDTH = 5;
  localparam int JTAG_DMI_SCAN_WIDTH = 41;
  localparam logic [JTAG_IR_WIDTH-1:0] JTAG_IR_IDCODE = 5'h01;
  localparam logic [JTAG_IR_WIDTH-1:0] JTAG_IR_DTMCS  = 5'h10;
  localparam logic [JTAG_IR_WIDTH-1:0] JTAG_IR_DMI    = 5'h11;

  // Debug status is observed from the product implementation; test stimulus
  // reaches it through DMI/JTAG rather than a top-level override port.
  assign debug_halted  = dut.debug_halted;
  assign debug_running = dut.debug_running;
  assign debug_pc      = dut.debug_pc;
  assign debug_cause   = dut.debug_cause;

  // Optional timing oracle: record the cycle at which the integrated APB
  // timer first asserts its PLIC source. The software report records the
  // first C-level ISR instruction, so the runner can derive source-to-ISR delay.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      timer_irq_prev <= 1'b0;
      plic_timer_source_seen <= 1'b0;
    end else begin
      if (has_plic_timer_source_report && !plic_timer_source_seen &&
          dut.timer_irq && !timer_irq_prev) begin
        $display("TB PLIC SOURCE ASSERT: source=%0d mcycle=%08h",
                 soc_pkg::PLIC_SRC_TIMER,
                 dut.riscv_core_i.ex_stage_i.csr_file_i.mcycle_q[31:0]);
        plic_timer_source_seen <= 1'b1;
      end
      timer_irq_prev <= dut.timer_irq;
    end
  end

  // MCU-LP-WFI-TIMER-01 must enter controller-managed WFI sleep, receive an
  // integrated TIMER0 source, and request the core clock back before its
  // software oracle verifies post-mret execution.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      low_power_sleep_seen <= 1'b0;
      low_power_timer_seen <= 1'b0;
      low_power_clint_seen <= 1'b0;
      low_power_wake_seen <= 1'b0;
    end else if (expect_low_power || tc_name == "MCU-LP-WFI-TIMER-01") begin
      if (dut.clk_rst_ctrl_i.sleep_q)
        low_power_sleep_seen <= 1'b1;
      if (dut.timer_irq && low_power_sleep_seen)
        low_power_timer_seen <= 1'b1;
      if (dut.clint_mtip && low_power_sleep_seen)
        low_power_clint_seen <= 1'b1;
      if (dut.cpu_wake && low_power_sleep_seen)
        low_power_wake_seen <= 1'b1;
    end
  end

  // The boot UART is a distinct pin from the runtime peripheral UART.  Queue
  // bytes in the TB, then serialize them synchronously at the configured boot
  // bit period so UART boot is exercised as an actual wire protocol.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      boot_uart_rx <= 1'b1;
      boot_uart_rd_index <= 0;
      boot_uart_bit_countdown <= 0;
      boot_uart_shift_byte <= 8'h00;
      boot_uart_bit_index <= 4'd0;
      boot_uart_active <= 1'b0;
    end else begin
      if (!boot_uart_active && (boot_uart_rd_index != boot_uart_wr_index)) begin
        boot_uart_shift_byte <= boot_uart_queue[boot_uart_rd_index % BOOT_UART_QUEUE_DEPTH];
        boot_uart_rd_index <= boot_uart_rd_index + 1;
        boot_uart_rx <= 1'b0;
        boot_uart_bit_index <= 4'd0;
        boot_uart_bit_countdown <= BOOT_UART_DIVISOR - 1;
        boot_uart_active <= 1'b1;
      end else if (boot_uart_active) begin
        if (boot_uart_bit_countdown != 0) begin
          boot_uart_bit_countdown <= boot_uart_bit_countdown - 1;
        end else begin
          boot_uart_bit_countdown <= BOOT_UART_DIVISOR - 1;
          if (boot_uart_bit_index < 4'd8) begin
            boot_uart_rx <= boot_uart_shift_byte[boot_uart_bit_index[2:0]];
            boot_uart_bit_index <= boot_uart_bit_index + 1;
          end else if (boot_uart_bit_index == 4'd8) begin
            boot_uart_rx <= 1'b1;
            boot_uart_bit_index <= 4'd9;
          end else begin
            boot_uart_rx <= 1'b1;
            boot_uart_active <= 1'b0;
          end
        end
      end else begin
        boot_uart_rx <= 1'b1;
      end
    end
  end

  assign plic_agent_active = (tc_name == "MCU-PLIC-IRQ-01") ||
                             (tc_name == "MCU-PLIC-SOURCE-SWEEP-01") ||
                             (tc_name == "MCU-PLIC-PENDING-PRIORITY-01");
  assign ext_irq = plic_agent_active ? ext_irq_agent : ext_irq_legacy;

  tb_plic_agent #(
    .EXT_IRQ_COUNT           (PLIC_EXT_IRQ_COUNT),
    .EXT_IRQ_FIRST_SOURCE_ID (PLIC_EXT_IRQ_FIRST)
  ) plic_agent_i (
    .clk              (clk),
    .rst_n            (rst_n),
    .active_i         (plic_agent_active),
    .single_irq_i     (tc_name == "MCU-PLIC-IRQ-01"),
    .source_sweep_i   (tc_name == "MCU-PLIC-SOURCE-SWEEP-01"),
    .priority_i       (tc_name == "MCU-PLIC-PENDING-PRIORITY-01"),
    .irq_ready_i      (dut.riscv_core_i.ex_stage_i.csr_file_i.mstatus_q[3] &&
                       dut.riscv_core_i.ex_stage_i.csr_file_i.mie_q[11]),
    .dbus_req_i       (dut.plic_req),
    .dbus_we_i        (dut.plic_we),
    .dbus_addr_i      (dut.plic_addr),
    .dbus_wdata_i     (dut.plic_wdata),
    .dbus_write_accept_i(dut.plic_write_accept),
    .dbus_resp_valid_i(dut.plic_resp_valid),
    .ext_irq_o        (ext_irq_agent),
    .done_o           (plic_agent_done)
  );

  // =========================================================================
  // Waveform dump
  // =========================================================================
  initial begin
    if ($test$plusargs("dump_wave")) begin
      if (!$value$plusargs("dump_file=%s", dump_file))
        dump_file = "waves/soc_tb.fst";
      $dumpfile(dump_file);
      $dumpvars(0, soc_tb);
      $display("TB WAVE: dumping to %s", dump_file);
    end
  end

  // =========================================================================
  // Shared helpers (copy of core TB pattern)
  `include "tb_common.svh"

  `include "tb_uart_agent.svh"

  `include "tb_spi_agent.svh"

  `include "tb_bus_monitor.svh"

  `include "tb_perf_profile.svh"

  `include "tb_irq_plic_agent.svh"

  `include "tb_debug_dmi_agent.svh"

  `include "tb_jtag_dmi_agent.svh"

  `include "tb_debug_scenarios.svh"

  initial begin
    @async_io_start;
    if (has_spi_miso_byte)
      drive_spi_slave_byte(spi_miso_byte[7:0], has_expected_spi_tx, expected_spi_tx_byte[7:0]);
  end

  initial begin
    @async_io_start;
    if (has_expected_uart_tx_bytes)
      expect_uart_tx_hex_string(expected_uart_tx_bytes);
    else if (has_expected_uart_tx) begin
      expect_uart_tx_byte(expected_uart_tx_byte[7:0]);
      uart_tx_done = 1'b1;
    end
  end

  initial begin
    @async_io_start;
    if (has_uart_rx_byte)
      drive_uart_rx_byte(uart_rx_byte[7:0]);
  end

  // =========================================================================
  // Test flow
  // =========================================================================
  initial begin
    // --- Parse plusargs ---
    if (!$value$plusargs("tc=%s", tc_name))
      $fatal(1, "No testcase selected. Pass +tc=<name>.");
    if (!$value$plusargs("instr_mem_file=%s", instr_mem_file))
      $fatal(1, "No instruction-memory file selected.");
    if (!$value$plusargs("boot_mode=%s", boot_mode_name))
      boot_mode_name = "bypass";
    has_jtag_boot_trace = $value$plusargs("jtag_boot_trace_file=%s", jtag_boot_trace_file);
    has_expected_regs   = $value$plusargs("expected_regs_file=%s", expected_regs_file);
    has_reference_output = $value$plusargs("reference_output_file=%s", reference_output_file);
    has_data_mem_file    = $value$plusargs("data_mem_file=%s", data_mem_file);
    has_expected_uart_tx = $value$plusargs("expected_uart_tx=%h", expected_uart_tx_byte);
    has_expected_uart_tx_bytes = $value$plusargs("expected_uart_tx_bytes=%s", expected_uart_tx_bytes);
    has_expected_uart_baud_div = $value$plusargs("expected_uart_baud_div=%d", expected_uart_baud_div);
    has_uart_rx_byte = $value$plusargs("uart_rx_byte=%h", uart_rx_byte);
    has_spi_miso_byte = $value$plusargs("spi_miso_byte=%h", spi_miso_byte);
    has_expected_spi_tx = $value$plusargs("expected_spi_tx=%h", expected_spi_tx_byte);
    if (!$value$plusargs("spi_transfer_count=%d", spi_transfer_count)) spi_transfer_count = 1;
    if (spi_transfer_count <= 0)
      $fatal(1, "spi_transfer_count must be positive.");
    has_expected_bus_errors = $value$plusargs("expected_bus_errors=%d", expected_bus_errors);
    has_completion = $value$plusargs("completion_reg=%d", completion_reg);
    if (has_completion && !$value$plusargs("completion_value=%h", completion_value))
      $fatal(1, "completion_reg requires completion_value.");
    if (has_completion && (completion_reg < 0 || completion_reg >= 32))
      $fatal(1, "completion_reg is out of range: %0d", completion_reg);

    if (!$value$plusargs("max_cycles=%d", max_cycles))          max_cycles = 80;
    if (!$value$plusargs("sig_base=%h", sig_base))              sig_base = 'h80;
    has_tohost = $value$plusargs("tohost_addr=%h", tohost_addr);
    if (!has_tohost)                                              tohost_addr = 'h0;
    has_expected_tohost_value = $value$plusargs("expected_tohost=%h", expected_tohost_value);
    has_expected_tohost_mask = $value$plusargs("expected_tohost_mask=%h", expected_tohost_mask);
    expect_low_power = $test$plusargs("expect_low_power");
    // `$test$plusargs` is prefix-matched: bare `perf_profile` would also
    // match `perf_profile_start_pc`. Require the exact enable token.
    perf_profile_en = $test$plusargs("perf_profile=1");
    if (!perf_profile_en && $test$plusargs("perf_profile_trace="))
      $fatal(1, "perf_profile_trace requires +perf_profile=1");
    if (has_expected_tohost_value && !has_tohost)
      $fatal(1, "expected_tohost requires tohost_addr.");
    if (has_expected_tohost_mask && !has_expected_tohost_value)
      $fatal(1, "expected_tohost_mask requires expected_tohost.");
    has_report_words = $value$plusargs("report_words_base=%h", report_words_base);
    if (has_report_words && !$value$plusargs("report_words_count=%d", report_words_count))
      $fatal(1, "report_words_base requires report_words_count.");
    has_plic_timer_source_report = $test$plusargs("report_plic_timer_source");
    if (has_report_words &&
        ((report_words_base < 0) || (report_words_count <= 0) ||
         ((report_words_base + report_words_count) > DATA_MEM_DEPTH)))
      $fatal(1, "report words range is out of DMEM bounds.");
    if (!$value$plusargs("boot_addr=%h", boot_addr_arg))        boot_addr_arg = soc_pkg::IMEM_BASE_ADDR;
    if (!$value$plusargs("irq_start_cycle=%d", irq_start_cycle)) irq_start_cycle = 0;
    if (!$value$plusargs("irq_duration=%d", irq_duration))       irq_duration = 0;
    if (!$value$plusargs("plic_src_cycle=%d", plic_src_cycle))   plic_src_cycle = 0;
    if (!$value$plusargs("plic_src_id=%d", plic_src_id))         plic_src_id = 0;
    if (!$value$plusargs("plic_src_duration=%d", plic_src_duration)) plic_src_duration = 0;
    if (!$value$plusargs("uart_baud_div=%d", uart_baud_div))     uart_baud_div = 8;
    if (!$value$plusargs("uart_rx_start_cycle=%d", uart_rx_start_cycle)) uart_rx_start_cycle = 80;
    if (!$value$plusargs("gpio_in=%h", gpio_in_value))           gpio_in_value = 0;
    has_expected_gpio_out = $value$plusargs("expected_gpio_out=%h", expected_gpio_out);
    has_expected_gpio_oe = $value$plusargs("expected_gpio_oe=%h", expected_gpio_oe);

    if (!has_expected_regs && !has_reference_output && !has_tohost &&
        !has_expected_uart_tx && !has_expected_uart_tx_bytes && !has_spi_miso_byte &&
        !has_expected_uart_baud_div &&
        !has_expected_gpio_out && !has_expected_gpio_oe)
      $fatal(1, "No oracle selected.");

    if (boot_mode_name == "bypass") begin
      boot_mode = 3'd0;
    end else if (boot_mode_name == "jtag_boot") begin
      boot_mode = 3'd1;
    end else if (boot_mode_name == "uart_boot") begin
      boot_mode = 3'd2;
    end else begin
      $fatal(1, "Unsupported boot_mode=%s (use bypass, jtag_boot, or uart_boot)", boot_mode_name);
    end
    if (has_jtag_boot_trace && (boot_mode_name != "jtag_boot"))
      $fatal(1, "jtag_boot_trace_file requires boot_mode=jtag_boot");

    $display("=== SoC testcase: %s ===", tc_name);
    $display("TB boot mode: %s", boot_mode_name);
    $display("TB loading instruction memory: %s", instr_mem_file);
    if (has_jtag_boot_trace)
      $display("TB JTAG host boot trace: %s", jtag_boot_trace_file);
    if (has_expected_regs)
      $display("TB expected-register oracle: %s", expected_regs_file);
    if (has_reference_output)
      $display("TB reference-output oracle: %s  sig_base=0x%0h  tohost=0x%0h",
               reference_output_file, sig_base, tohost_addr);
    boot_addr = boot_addr_arg;
    $display("TB boot address: 0x%016h", boot_addr);
    $display("TB local-memory read latency: imem=1 dmem=1 (product fixed)");
    if (perf_profile_en)
      $display("TB PERF PROFILE: enabled");
    if (irq_duration != 0)
      $display("TB IRQ: ext_irq source %0d start=%0d duration=%0d",
               PLIC_EXT_IRQ_FIRST, irq_start_cycle, irq_duration);
    if (has_expected_uart_tx)
      $display("TB UART TX oracle: byte=0x%02h baud_div=%0d", expected_uart_tx_byte[7:0], uart_baud_div);
    if (has_expected_uart_tx_bytes)
      $display("TB UART TX oracle: bytes=%s baud_div=%0d", expected_uart_tx_bytes, uart_baud_div);
    if (has_uart_rx_byte)
      $display("TB UART RX stimulus: byte=0x%02h baud_div=%0d start_period=%0d",
               uart_rx_byte[7:0], uart_baud_div, uart_rx_start_cycle);
    if (has_expected_uart_baud_div)
      $display("TB UART BAUDDIV oracle: expected=%0d", expected_uart_baud_div);
    if (has_spi_miso_byte)
      $display("TB SPI slave stimulus: miso_byte=0x%02h transfers=%0d", spi_miso_byte[7:0], spi_transfer_count);
    if (has_expected_spi_tx)
      $display("TB SPI MOSI oracle: expected=0x%02h", expected_spi_tx_byte[7:0]);
    if (has_expected_bus_errors)
      $display("TB bus-error oracle: expected count=%0d", expected_bus_errors);
    if (has_expected_gpio_out)
      $display("TB GPIO OUT oracle: expected=%08h", expected_gpio_out);
    if (has_expected_gpio_oe)
      $display("TB GPIO OE oracle: expected=%08h", expected_gpio_oe);
    if (has_completion)
      $display("TB completion oracle: x%0d=%08h", completion_reg, completion_value);
    if (has_report_words)
      $display("TB report words: base=%0d count=%0d", report_words_base, report_words_count);
    if (has_plic_timer_source_report)
      $display("TB PLIC source timing: integrated timer source enabled");

    // --- Default SoC port states ---
    boot_uart_wr_index = 0;
    uart_rx       = 1'b1;
    gpio_in       = gpio_in_value[31:0];
    spi_miso      = 1'b0;
    spi_slave_done = 1'b0;
    uart_tx_done   = 1'b0;
    uart_rx_done   = 1'b0;
    jtag_tck      = 1'b0;
    jtag_tms      = 1'b0;
    jtag_tdi      = 1'b0;
    jtag_trst_n   = 1'b0;

    // --- Load memories ---
    init_instruction_memory(RV32I_NOP);
    init_data_memory((boot_mode_name == "bypass") ? 32'h0000_0000 : 32'ha5a5_5a5a);
    if (boot_mode_name == "bypass") begin
      $readmemh(instr_mem_file, dut.instr_mem_i.sram_i.mem);
    end else begin
      $display("TB boot loader will install instruction memory: %s", instr_mem_file);
    end
    if (has_data_mem_file && (boot_mode_name == "bypass")) begin
      $display("TB loading data memory: %s", data_mem_file);
      $readmemh(data_mem_file, dut.data_mem_i.sram_i.mem);
    end else if (has_data_mem_file) begin
      $display("TB boot fidelity: ignoring preloaded data memory; crt0 initializes DMEM from IMEM");
    end

    // --- Reset ---
    rst_n          = 1'b1;
    fetch_enable_i = 1'b1;
    ext_irq_legacy = '0;
    run_cycle        = 0;
    #1;
    rst_n = 1'b0;
    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);

    if (boot_mode_name == "jtag_boot") begin
      jtag_reset_tap();
      if (has_jtag_boot_trace)
        load_instruction_memory_via_jtag_boot_trace(jtag_boot_trace_file);
      else
        load_instruction_memory_via_jtag_boot(instr_mem_file);
    end else if (boot_mode_name == "uart_boot") begin
      load_instruction_memory_via_uart_boot(instr_mem_file);
    end
    -> async_io_start;

    // --- Run ---
    if (has_reference_output || has_tohost) begin
      tohost_matched = 1'b0;
      tohost_observed = 32'h0;
      repeat (max_cycles) begin
        @(posedge clk);
        if (dut.data_mem_i.sram_i.mem[tohost_addr] !== 32'h0) begin
          tohost_observed = dut.data_mem_i.sram_i.mem[tohost_addr];
          if (!has_expected_tohost_value ||
              (!has_expected_tohost_mask &&
               (tohost_observed === expected_tohost_value)) ||
              (has_expected_tohost_mask &&
               ((tohost_observed & expected_tohost_mask) ===
                (expected_tohost_value & expected_tohost_mask)))) begin
            tohost_matched = 1'b1;
            $display("TB INFO: tohost reached value=%08h", tohost_observed);
          end else begin
            if (has_expected_tohost_mask)
              $display("TB ERROR: tohost expected=%08h mask=%08h got=%08h",
                       expected_tohost_value, expected_tohost_mask, tohost_observed);
            else
              $display("TB ERROR: tohost expected=%08h got=%08h",
                       expected_tohost_value, tohost_observed);
          end
          break;
        end
      end
      $display("TB CHECK: tohost=%08h", tohost_observed);
      if (!tohost_matched)
        $display("%s FAIL: tohost not reached", TB_PHASE_NAME);
    end else if (tc_name == "MCU-DEBUG-ABSTRACT-01") begin
      repeat (20) @(posedge clk);
      run_debug_abstract_test();
      repeat (5) @(posedge clk);
    end else if (tc_name == "MCU-DEBUG-GPR-SWEEP-01") begin
      repeat (20) @(posedge clk);
      run_debug_gpr_sweep_test();
      repeat (5) @(posedge clk);
    end else if (tc_name == "MCU-DEBUG-COMPLETE-01") begin
      repeat (20) @(posedge clk);
      run_debug_completeness_test();
      repeat (5) @(posedge clk);
    end else if (tc_name == "MCU-DEBUG-JTAG-01") begin
      repeat (20) @(posedge clk);
      run_debug_jtag_test();
      repeat (5) @(posedge clk);
    end else if (tc_name == "MCU-DEBUG-JTAG-STRESS-01") begin
      repeat (20) @(posedge clk);
      run_debug_jtag_stress_test();
      repeat (5) @(posedge clk);
    end else if (tc_name == "MCU-DEBUG-OPENOCD-LIKE-01") begin
      repeat (20) @(posedge clk);
      run_debug_openocd_like_test();
      repeat (5) @(posedge clk);
    end else if (tc_name == "MCU-DEBUG-TRIGGER-SBA-01") begin
      repeat (20) @(posedge clk);
      run_debug_trigger_sba_test();
      repeat (5) @(posedge clk);
    end else begin
      completion_seen = 1'b0;
      repeat (max_cycles) begin
        @(posedge clk);
        if (has_completion &&
            (dut.riscv_core_i.id_stage_i.regfile_i.regs_q[completion_reg] === completion_value)) begin
          completion_seen = 1'b1;
          break;
        end
      end
      if (has_completion)
        check(completion_seen,
              $sformatf("completion x%0d=%08h not seen before max_cycles expired",
                        completion_reg, completion_value));
    end

    #1;

    if (has_spi_miso_byte) begin
      check(spi_slave_done, "SPI slave transaction did not complete before max_cycles expired");
    end
    if (has_expected_bus_errors) begin
      check(observed_bus_errors == expected_bus_errors,
            $sformatf("bus-error count expected %0d, got %0d",
                      expected_bus_errors, observed_bus_errors));
      $display("TB CHECK: bus-error count expected=%0d actual=%0d PASS",
               expected_bus_errors, observed_bus_errors);
    end
    if (has_expected_gpio_out)
      check(gpio_out === expected_gpio_out[31:0],
            $sformatf("GPIO OUT expected %08h, got %08h", expected_gpio_out, gpio_out));
    if (has_expected_gpio_oe)
      check(gpio_oe === expected_gpio_oe[31:0],
            $sformatf("GPIO OE expected %08h, got %08h", expected_gpio_oe, gpio_oe));
    if (has_expected_uart_baud_div)
      check(dut.uart0_i.baud_div_q === expected_uart_baud_div[31:0],
            $sformatf("UART BAUDDIV expected %0d, got %0d",
                      expected_uart_baud_div, dut.uart0_i.baud_div_q));
    if (has_report_words) begin
      for (int report_index = 0; report_index < report_words_count; report_index++)
        $display("TB REPORT: word[%0d]=%08h", report_index,
                 dut.data_mem_i.sram_i.mem[report_words_base + report_index]);
    end

    if (tc_name == "MCU-LP-WFI-TIMER-01") begin
      check(low_power_sleep_seen, "WFI did not enter controller-managed sleep");
      check(low_power_timer_seen, "TIMER0 did not assert while the core was asleep");
      check(low_power_wake_seen, "TIMER0 PLIC interrupt did not request a core wake");
      $display("TB LOW POWER: WFI -> TIMER0 -> PLIC -> wake PASS");
    end
    if (expect_low_power) begin
      check(low_power_sleep_seen, "Zephyr idle did not enter controller-managed WFI sleep");
      check(low_power_clint_seen, "CLINT MTIP did not assert while Zephyr was asleep");
      check(low_power_wake_seen, "CLINT wake did not request the core clock");
      $display("TB LOW POWER: WFI -> CLINT -> wake PASS");
    end

    // --- Check results ---
    if (has_expected_regs) begin
      compare_expected_registers(expected_regs_file);
    end
    if (has_reference_output || has_tohost) begin
      if (tohost_matched) begin
        $display("%s PASS: %s", TB_PHASE_NAME, tc_name);
      end else begin
        $display("%s FAIL: %s", TB_PHASE_NAME, tc_name);
      end
    end else begin
      $display("%s PASS: %s", TB_PHASE_NAME, tc_name);
    end
    if (perf_profile_en)
      report_perf_profile();
    if (has_expected_uart_tx || has_expected_uart_tx_bytes) begin
      check(uart_tx_done, "UART TX oracle did not complete before max_cycles expired");
    end
    if (has_uart_rx_byte) begin
      check(uart_rx_done, "UART RX stimulus did not complete before max_cycles expired");
    end
    $finish;
  end

endmodule
