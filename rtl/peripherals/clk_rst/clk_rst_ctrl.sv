// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

module clk_rst_ctrl (
  input  logic        clk_sys,
  input  logic        por_n_i,

  input  logic        psel_i,
  input  logic        penable_i,
  input  logic        pwrite_i,
  input  logic [31:0] paddr_i,
  input  logic [31:0] pwdata_i,
  input  logic [3:0]  pstrb_i,
  output logic        pready_o,
  output logic [31:0] prdata_o,
  output logic        pslverr_o,

  input  logic        ext_rst_n_i,
  input  logic        wdt_rst_n_i,
  input  logic        wdt_pretimeout_i,
  input  logic        wdt_enabled_i,
  input  logic        wdt_locked_i,
  input  logic        uart_rx_i,
  input  logic [7:0]  gpio_i,
  input  logic        clint_mtip_i,
  input  logic        cpu_wfi_i,
  input  logic        cpu_irq_pending_i,
  input  logic        debug_halt_req_i,
  input  logic [4:0]  peri_busy_i,

  output logic        cpu_wake_o,
  output logic        core_clk_en_o,
  output logic [4:0]  peri_clk_en_o,
  output logic [4:0]  peri_rst_n_o,
  output logic        sys_rst_n_o
);

  localparam logic [7:0] REG_CLK_EN      = 8'h00;
  localparam logic [7:0] REG_CLK_STATUS  = 8'h04;
  localparam logic [7:0] REG_PERI_RST    = 8'h08;
  localparam logic [7:0] REG_RST_CAUSE   = 8'h0c;
  localparam logic [7:0] REG_SLEEP_CTRL  = 8'h10;
  localparam logic [7:0] REG_WAKE_EN     = 8'h14;
  localparam logic [7:0] REG_WAKE_STATUS = 8'h18;
  localparam logic [7:0] REG_SOFT_RST    = 8'h1c;

  localparam logic [4:0] RST_CAUSE_POR = 5'b00001;
  localparam logic [4:0] RST_CAUSE_EXT = 5'b00010;
  localparam logic [4:0] RST_CAUSE_WDT = 5'b00100;
  localparam logic [4:0] RST_CAUSE_SW  = 5'b01000;

  logic        apb_access;
  logic        valid_offset;
  logic [7:0]  reg_offset;
  logic [31:0] write_mask;
  logic        soft_reset_req;
  logic [4:0]  peri_reset_req;
  logic        sleep_req_set;

  logic [4:0]  clk_en_q;
  logic        wfi_sleep_en_q;
  logic [10:0] wake_en_q;
  logic [10:0] wake_status_q;
  logic [4:0]  reset_cause_q;
  logic        sleep_req_q;
  logic        sleep_q;

  logic        ext_rst_meta_q;
  logic        ext_rst_sync_q;
  logic        wdt_rst_prev_q;
  logic [4:0]  sys_reset_count_q;
  logic        wdt_reset_event;
  logic        warm_reset_event;

  logic        uart_rx_meta_q;
  logic        uart_rx_sync_q;
  logic        uart_rx_prev_q;
  logic [7:0]  gpio_meta_q;
  logic [7:0]  gpio_sync_q;
  logic [7:0]  gpio_prev_q;
  logic [10:0] wake_raw;
  logic [10:0] wake_hit;
  logic        wake_nonmaskable;
  logic        capture_wake;

  logic [4:0] peri_reset_active;
  logic [4:0] peri_release_active;
  logic [4:0] peri_reset_count_q [0:4];
  logic [1:0] peri_release_count_q [0:4];

  assign apb_access = psel_i & penable_i;
  assign reg_offset = paddr_i[7:0];
  assign valid_offset = (reg_offset == REG_CLK_EN) ||
                        (reg_offset == REG_CLK_STATUS) ||
                        (reg_offset == REG_PERI_RST) ||
                        (reg_offset == REG_RST_CAUSE) ||
                        (reg_offset == REG_SLEEP_CTRL) ||
                        (reg_offset == REG_WAKE_EN) ||
                        (reg_offset == REG_WAKE_STATUS) ||
                        (reg_offset == REG_SOFT_RST);
  assign write_mask = {{8{pstrb_i[3]}}, {8{pstrb_i[2]}},
                       {8{pstrb_i[1]}}, {8{pstrb_i[0]}}};

  assign pready_o  = 1'b1;
  assign pslverr_o = apb_access && ((!valid_offset) || (paddr_i[1:0] != 2'b00));

  assign soft_reset_req = apb_access && pwrite_i && !pslverr_o &&
                          (reg_offset == REG_SOFT_RST) && pstrb_i[0] && pwdata_i[0];
  assign peri_reset_req = (apb_access && pwrite_i && !pslverr_o &&
                           (reg_offset == REG_PERI_RST) && pstrb_i[0]) ?
                          (pwdata_i[4:0] & {~wdt_locked_i, 4'hf}) : 5'h00;
  assign sleep_req_set = apb_access && pwrite_i && !pslverr_o &&
                         (reg_offset == REG_SLEEP_CTRL) && pstrb_i[0] && pwdata_i[0];

  always_comb begin
    unique case (reg_offset)
      REG_CLK_EN:      prdata_o = {27'h0, clk_en_q};
      REG_CLK_STATUS:  prdata_o = {27'h0, peri_clk_en_o};
      REG_PERI_RST:    prdata_o = 32'h0000_0000;
      REG_RST_CAUSE:   prdata_o = {27'h0, reset_cause_q};
      REG_SLEEP_CTRL:  prdata_o = {29'h0, wfi_sleep_en_q, 2'b00};
      REG_WAKE_EN:     prdata_o = {21'h0, wake_en_q};
      REG_WAKE_STATUS: prdata_o = {21'h0, wake_status_q};
      REG_SOFT_RST:    prdata_o = 32'h0000_0000;
      default:         prdata_o = 32'h0000_0000;
    endcase
  end

  // Reset inputs are observed in the root-clock domain. External reset also
  // asserts sys_rst_n_o asynchronously through the output equation below.
  always_ff @(posedge clk_sys or negedge por_n_i) begin
    if (!por_n_i) begin
      ext_rst_meta_q <= 1'b1;
      ext_rst_sync_q <= 1'b1;
      wdt_rst_prev_q <= 1'b1;
    end else begin
      ext_rst_meta_q <= ext_rst_n_i;
      ext_rst_sync_q <= ext_rst_meta_q;
      wdt_rst_prev_q <= wdt_rst_n_i;
    end
  end

  assign wdt_reset_event = wdt_rst_prev_q & ~wdt_rst_n_i;
  assign warm_reset_event = !ext_rst_sync_q || wdt_reset_event || soft_reset_req;

  always_ff @(posedge clk_sys or negedge por_n_i) begin
    if (!por_n_i) begin
      sys_reset_count_q <= 5'd0;
      reset_cause_q <= RST_CAUSE_POR;
    end else begin
      if (!ext_rst_sync_q) begin
        sys_reset_count_q <= 5'd16;
        reset_cause_q <= RST_CAUSE_EXT;
      end else if (wdt_reset_event) begin
        sys_reset_count_q <= 5'd16;
        reset_cause_q <= RST_CAUSE_WDT;
      end else if (soft_reset_req) begin
        sys_reset_count_q <= 5'd16;
        reset_cause_q <= RST_CAUSE_SW;
      end else if (sys_reset_count_q != 5'd0) begin
        sys_reset_count_q <= sys_reset_count_q - 5'd1;
      end
    end
  end

  // Keep asynchronous assertion, but prevent an external-reset release from
  // reaching downstream domains before it has passed the root-clock
  // synchronizer and the warm-reset hold interval.
  assign sys_rst_n_o = por_n_i & ext_rst_n_i & ext_rst_sync_q &
                       (sys_reset_count_q == 5'd0);

  // Synchronize asynchronous pin wake inputs and detect falling edges.
  always_ff @(posedge clk_sys or negedge por_n_i) begin
    if (!por_n_i) begin
      uart_rx_meta_q <= 1'b1;
      uart_rx_sync_q <= 1'b1;
      uart_rx_prev_q <= 1'b1;
      gpio_meta_q <= 8'hff;
      gpio_sync_q <= 8'hff;
      gpio_prev_q <= 8'hff;
    end else begin
      uart_rx_meta_q <= uart_rx_i;
      uart_rx_sync_q <= uart_rx_meta_q;
      uart_rx_prev_q <= uart_rx_sync_q;
      gpio_meta_q <= gpio_i;
      gpio_sync_q <= gpio_meta_q;
      gpio_prev_q <= gpio_sync_q;
    end
  end

  assign wake_raw = {wdt_pretimeout_i, clint_mtip_i,
                     (gpio_prev_q & ~gpio_sync_q),
                     (uart_rx_prev_q & ~uart_rx_sync_q)};
  assign wake_hit = wake_raw & wake_en_q;
  assign wake_nonmaskable = cpu_irq_pending_i | debug_halt_req_i;
  assign capture_wake = sleep_req_q | sleep_q |
                        (cpu_wfi_i & wfi_sleep_en_q);

  // Software-visible configuration and wake status. Warm reset returns all
  // ordinary controls to boot-safe defaults while preserving reset_cause_q.
  always_ff @(posedge clk_sys or negedge por_n_i) begin
    if (!por_n_i) begin
      clk_en_q <= 5'h1f;
      wfi_sleep_en_q <= 1'b0;
      wake_en_q <= 11'h000;
      wake_status_q <= 11'h000;
    end else if (warm_reset_event) begin
      clk_en_q <= 5'h1f;
      wfi_sleep_en_q <= 1'b0;
      wake_en_q <= 11'h000;
      wake_status_q <= 11'h000;
    end else begin
      if (apb_access && pwrite_i && !pslverr_o) begin
        unique case (reg_offset)
          REG_CLK_EN:
            clk_en_q <= (clk_en_q & ~write_mask[4:0]) |
                        (pwdata_i[4:0] & write_mask[4:0]);
          REG_SLEEP_CTRL:
            if (pstrb_i[0]) wfi_sleep_en_q <= pwdata_i[2];
          REG_WAKE_EN:
            wake_en_q <= (wake_en_q & ~write_mask[10:0]) |
                         (pwdata_i[10:0] & write_mask[10:0]);
          REG_WAKE_STATUS:
            wake_status_q <= wake_status_q & ~(pwdata_i[10:0] & write_mask[10:0]);
          default: ;
        endcase
      end

      if (capture_wake && (|wake_hit))
        wake_status_q <= wake_status_q | wake_hit;
    end
  end

  // WFI handshake. cpu_wake_o is asserted while the root clock has already
  // requested the core clock on; the gate wrapper makes it visible at the next
  // core rising edge.
  always_ff @(posedge clk_sys or negedge por_n_i) begin
    if (!por_n_i) begin
      sleep_req_q <= 1'b0;
      sleep_q <= 1'b0;
      core_clk_en_o <= 1'b1;
      cpu_wake_o <= 1'b0;
    end else if (warm_reset_event) begin
      sleep_req_q <= 1'b0;
      sleep_q <= 1'b0;
      core_clk_en_o <= 1'b1;
      cpu_wake_o <= 1'b0;
    end else begin
      cpu_wake_o <= 1'b0;
      if (sleep_req_set)
        sleep_req_q <= 1'b1;

      if (sleep_q) begin
        if ((|wake_hit) || wake_nonmaskable) begin
          sleep_q <= 1'b0;
          sleep_req_q <= 1'b0;
          core_clk_en_o <= 1'b1;
          cpu_wake_o <= 1'b1;
        end
      end else if (cpu_wfi_i && (sleep_req_q || wfi_sleep_en_q)) begin
        sleep_req_q <= 1'b0;
        if ((|wake_hit) || wake_nonmaskable) begin
          core_clk_en_o <= 1'b1;
          cpu_wake_o <= 1'b1;
        end else begin
          sleep_q <= 1'b1;
          core_clk_en_o <= 1'b0;
        end
      end
    end
  end

  // Per-domain reset pulse and clock-release extension.
  always_ff @(posedge clk_sys or negedge por_n_i) begin
    if (!por_n_i) begin
      for (int reset_index = 0; reset_index < 5; reset_index++) begin
        peri_reset_count_q[reset_index] <= 5'd0;
        peri_release_count_q[reset_index] <= 2'd0;
      end
    end else if (warm_reset_event) begin
      for (int reset_index = 0; reset_index < 5; reset_index++) begin
        peri_reset_count_q[reset_index] <= 5'd0;
        peri_release_count_q[reset_index] <= 2'd0;
      end
    end else begin
      for (int reset_index = 0; reset_index < 5; reset_index++) begin
        if (peri_reset_req[reset_index]) begin
          peri_reset_count_q[reset_index] <= 5'd16;
          peri_release_count_q[reset_index] <= 2'd0;
        end else if (peri_reset_count_q[reset_index] != 5'd0) begin
          peri_reset_count_q[reset_index] <= peri_reset_count_q[reset_index] - 5'd1;
          if (peri_reset_count_q[reset_index] == 5'd1)
            peri_release_count_q[reset_index] <= 2'd2;
        end else if (peri_release_count_q[reset_index] != 2'd0) begin
          peri_release_count_q[reset_index] <= peri_release_count_q[reset_index] - 2'd1;
        end
      end
    end
  end

  always_comb begin
    for (int reset_index = 0; reset_index < 5; reset_index++) begin
      peri_reset_active[reset_index] = (peri_reset_count_q[reset_index] != 5'd0);
      peri_release_active[reset_index] = (peri_release_count_q[reset_index] != 2'd0);
    end
  end

  // A software gate request is deferred until the affected domain is idle.
  // This prevents an in-flight UART/SPI byte or enabled timer from being
  // truncated by a direct CLK_EN write.
  // UART RX wake keeps the UART sampler/FIFO clocked so that the start bit
  // which woke the core is not lost before software resumes.
  assign peri_clk_en_o = clk_en_q | peri_busy_i | peri_reset_active | peri_release_active |
                         {wdt_enabled_i, 4'h0} | {4'h0, wake_en_q[0]};
  assign peri_rst_n_o = {5{sys_rst_n_o}} & ~peri_reset_active;

endmodule
