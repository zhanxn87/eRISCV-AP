// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

  // Simple SPI responder for APB SPI directed tests.
  task automatic drive_spi_slave_byte(input logic [7:0] miso_data,
                                      input bit check_mosi,
                                      input logic [7:0] expected_mosi);
    int bit_index;
    int transaction;
    logic [7:0] actual_mosi;
    begin
      for (transaction = 0; transaction < spi_transfer_count; transaction = transaction + 1) begin
        actual_mosi = 8'h00;
        spi_miso = miso_data[7];
        wait (spi_ss[0] === 1'b0);
        for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
          @(posedge spi_sclk);
          actual_mosi[bit_index] = spi_mosi;
          if (bit_index != 0) begin
            @(negedge spi_sclk);
            spi_miso = miso_data[bit_index - 1];
          end
        end
        if (check_mosi) begin
          check(actual_mosi === expected_mosi,
                $sformatf("SPI MOSI expected 0x%02h, got 0x%02h (transaction %0d)",
                          expected_mosi, actual_mosi, transaction));
        end
        $display("TB SPI: transaction=%0d MOSI=0x%02h MISO=0x%02h PASS",
                 transaction, actual_mosi, miso_data);
      end
      spi_slave_done = 1'b1;
    end
  endtask
