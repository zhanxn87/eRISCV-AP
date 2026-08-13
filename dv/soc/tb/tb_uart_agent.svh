// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: BSD-3-Clause

  // Runtime UART helper tasks for directed peripheral tests.
  task automatic wait_uart_bit_period(input int periods);
    int period_index;
    int cycle_index;
    begin
      for (period_index = 0; period_index < periods; period_index = period_index + 1) begin
        for (cycle_index = 0; cycle_index < uart_baud_div; cycle_index = cycle_index + 1) begin
          @(posedge clk);
        end
      end
    end
  endtask

  task automatic drive_uart_rx_byte(input logic [7:0] data);
    int bit_index;
    begin
      uart_rx = 1'b1;
      wait_uart_bit_period(uart_rx_start_cycle);
      uart_rx = 1'b0;
      wait_uart_bit_period(1);
      for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
        uart_rx = data[bit_index];
        wait_uart_bit_period(1);
      end
      uart_rx = 1'b1;
      wait_uart_bit_period(1);
      uart_rx_done = 1'b1;
      $display("TB UART RX: drove byte 0x%02h", data);
    end
  endtask

  task automatic enqueue_boot_uart_byte(input logic [7:0] data);
    begin
      // Stream arbitrarily large images through a bounded queue instead of
      // requiring a TB buffer proportional to instruction memory size.
      while ((boot_uart_wr_index - boot_uart_rd_index) >= (BOOT_UART_QUEUE_DEPTH - 1))
        @(posedge clk);
      boot_uart_queue[boot_uart_wr_index % BOOT_UART_QUEUE_DEPTH] = data;
      boot_uart_wr_index = boot_uart_wr_index + 1;
    end
  endtask

  task automatic enqueue_boot_uart_word(input logic [31:0] word);
    begin
      enqueue_boot_uart_byte(8'h02);
      enqueue_boot_uart_byte(word[7:0]);
      enqueue_boot_uart_byte(word[15:8]);
      enqueue_boot_uart_byte(word[23:16]);
      enqueue_boot_uart_byte(word[31:24]);
    end
  endtask

  task automatic enqueue_boot_uart_address(input logic [31:0] word_addr);
    begin
      enqueue_boot_uart_byte(8'h01);
      enqueue_boot_uart_byte(word_addr[7:0]);
      enqueue_boot_uart_byte(word_addr[15:8]);
      enqueue_boot_uart_byte(word_addr[23:16]);
      enqueue_boot_uart_byte(word_addr[31:24]);
    end
  endtask

  // Load an image over the dedicated boot UART, using the protocol consumed
  // by uart_boot_slave rather than a behavioral memory preload.
  task automatic load_instruction_memory_via_uart_boot(input string image_file);
    int file;
    int status;
    int index;
    string line;
    logic [31:0] word;
    begin
      file = $fopen(image_file, "r");
      if (file == 0)
        $fatal(1, "Unable to open instruction-memory file for UART boot: %s", image_file);

      enqueue_boot_uart_byte(8'h03); // hold fetch
      enqueue_boot_uart_byte(8'h06); // reset address
      enqueue_boot_uart_byte(8'h05); // set auto-increment
      enqueue_boot_uart_byte(8'h01);
      index = 0;
      while ($fgets(line, file)) begin
        status = $sscanf(line, "@%h", index);
        if (status == 1) begin
          check(index < INSTR_MEM_DEPTH, "UART boot instruction image address exceeds instruction memory depth");
          enqueue_boot_uart_address(index);
        end else begin
          status = $sscanf(line, "%h", word);
        end
        if (status == 1 && line[0] != "@") begin
          check(index < INSTR_MEM_DEPTH, "UART boot instruction image exceeds instruction memory depth");
          enqueue_boot_uart_word(word);
          index = index + 1;
        end else if (status != 1) begin
          $fatal(1, "Malformed instruction-memory file: %s", image_file);
        end
      end
      $fclose(file);

      enqueue_boot_uart_byte(8'h04); // release fetch
      while ((boot_uart_rd_index != boot_uart_wr_index) || boot_uart_active)
        @(posedge clk);
      repeat (4 * BOOT_UART_DIVISOR) @(posedge clk);
      check(!boot_uart_protocol_error, "UART boot protocol error asserted");
      check(!boot_uart_overrun, "UART boot receiver overrun asserted");
      $display("TB UART BOOT: completed image through boot UART; next word address=%0d", index);
    end
  endtask

  task automatic expect_uart_tx_byte(input logic [7:0] expected);
    int bit_index;
    logic [7:0] actual;
    begin
      actual = 8'h00;
      wait (uart_tx === 1'b0);
      wait_uart_bit_period(1);
      repeat (uart_baud_div / 2) @(posedge clk);
      for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
        actual[bit_index] = uart_tx;
        wait_uart_bit_period(1);
      end
      check(uart_tx === 1'b1, "UART TX stop bit was not high");
      check(actual === expected,
            $sformatf("UART TX expected 0x%02h, got 0x%02h", expected, actual));
      $display("TB UART TX: expected=0x%02h actual=0x%02h PASS", expected, actual);
    end
  endtask

  function automatic logic [3:0] hex_to_nibble(input byte character);
    begin
      if ((character >= "0") && (character <= "9")) begin
        hex_to_nibble = 4'(character - 8'd48);
      end else if ((character >= "a") && (character <= "f")) begin
        hex_to_nibble = 4'(character - 8'd87);
      end else if ((character >= "A") && (character <= "F")) begin
        hex_to_nibble = 4'(character - 8'd55);
      end else begin
        $fatal(1, "Invalid UART TX hex-string character: %c", character);
      end
    end
  endfunction

  task automatic expect_uart_tx_hex_string(input string expected_hex);
    int byte_index;
    int byte_count;
    byte high_char;
    byte low_char;
    logic [7:0] expected;
    begin
      check((expected_hex.len() % 2) == 0, "UART TX hex-string oracle must have an even number of characters");
      byte_count = expected_hex.len() / 2;
      for (byte_index = 0; byte_index < byte_count; byte_index = byte_index + 1) begin
        high_char = expected_hex.getc(byte_index * 2);
        low_char  = expected_hex.getc(byte_index * 2 + 1);
        expected  = {hex_to_nibble(high_char), hex_to_nibble(low_char)};
        expect_uart_tx_byte(expected);
      end
      uart_tx_done = 1'b1;
      $display("TB UART TX: %0d byte sequence PASS", byte_count);
    end
  endtask
