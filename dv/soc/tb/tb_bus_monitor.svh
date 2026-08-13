// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

  // DBus response/error signals are registered at posedge.  Sample on the
  // following negedge, after the NBA updates have settled, so every one-cycle
  // response is observed once and back-to-back error responses remain distinct.
  always @(negedge clk or negedge rst_n) begin
    if (!rst_n) begin
      observed_bus_errors <= 0;
    end else if (dut.data_resp_valid && dut.data_err) begin
      observed_bus_errors <= observed_bus_errors + 1;
      $display("TB BUS ERROR: addr=%08h we=%0b observed_count=%0d",
               dut.data_addr, dut.data_we, observed_bus_errors + 1);
    end
  end
