// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

  // Legacy cycle-scheduled external source stimulus. All events use the PLIC
  // path; no testbench signal bypasses the interrupt controller.
  // Product PLIC scenarios are driven by tb_plic_agent.sv from bus events.
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      run_cycle       <= 0;
      ext_irq_legacy <= '0;
    end else if (fetch_enable_i) begin
      ext_irq_legacy <= '0;
      if (irq_duration != 0 && run_cycle >= irq_start_cycle &&
          run_cycle < irq_start_cycle + irq_duration)
        ext_irq_legacy[0] <= 1'b1;

      if (plic_src_duration != 0 && run_cycle >= plic_src_cycle &&
          run_cycle < plic_src_cycle + plic_src_duration &&
          plic_src_id >= PLIC_EXT_IRQ_FIRST &&
          plic_src_id < PLIC_EXT_IRQ_FIRST + PLIC_EXT_IRQ_COUNT)
        ext_irq_legacy[plic_src_id - PLIC_EXT_IRQ_FIRST] <= 1'b1;

      run_cycle <= run_cycle + 1;
    end else begin
      ext_irq_legacy <= '0;
    end
  end
