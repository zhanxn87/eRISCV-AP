/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "uart.h"

#define ERISCV_MCU_UART_ASYNC_TX_BUFFER_SIZE 128u
#define ERISCV_MCU_UART_ASYNC_RX_BUFFER_SIZE 128u
#define ERISCV_MCU_UART_ASYNC_TX_WATERMARK   8u
#define ERISCV_MCU_UART_ASYNC_RX_WATERMARK   1u

static eriscv_mcu_u32 tx_buffer[ERISCV_MCU_UART_ASYNC_TX_BUFFER_SIZE]
    __attribute__((section(".noinit")));
static eriscv_mcu_u32 rx_buffer[ERISCV_MCU_UART_ASYNC_RX_BUFFER_SIZE]
    __attribute__((section(".noinit")));
static volatile eriscv_mcu_u32 tx_head __attribute__((section(".noinit")));
static volatile eriscv_mcu_u32 tx_tail __attribute__((section(".noinit")));
static volatile eriscv_mcu_u32 rx_head __attribute__((section(".noinit")));
static volatile eriscv_mcu_u32 rx_tail __attribute__((section(".noinit")));
static volatile eriscv_mcu_u32 rx_dropped __attribute__((section(".noinit")));

static eriscv_mcu_u32 uart_irq_save(void) {
  eriscv_mcu_u32 mstatus;

  __asm__ volatile ("csrr %0, mstatus" : "=r"(mstatus));
  __asm__ volatile ("csrc mstatus, %0" :: "r"(ERISCV_MCU_MSTATUS_MIE) : "memory");
  return mstatus;
}

static void uart_irq_restore(eriscv_mcu_u32 mstatus) {
  if ((mstatus & ERISCV_MCU_MSTATUS_MIE) != 0u) {
    __asm__ volatile ("csrs mstatus, %0" :: "r"(ERISCV_MCU_MSTATUS_MIE) : "memory");
  }
}

static eriscv_mcu_u32 uart_ring_next(eriscv_mcu_u32 index, eriscv_mcu_u32 size) {
  return (index + 1u) & (size - 1u);
}

static eriscv_mcu_u32 uart_load_byte(const char *data, eriscv_mcu_u32 index) {
  eriscv_mcu_u32 address = (eriscv_mcu_u32)data + index;
  eriscv_mcu_u32 word = *(volatile const eriscv_mcu_u32 *)(address & ~3u);

  return (word >> ((address & 3u) * 8u)) & 0xffu;
}

static void uart_tx_service(void) {
  eriscv_mcu_u32 ctrl;

  while ((tx_tail != tx_head) &&
         ((eriscv_mcu_mmio_read32(ERISCV_MCU_UART0_BASE + ERISCV_MCU_UART_STATUS) &
           ERISCV_MCU_UART_STATUS_TX_READY) != 0u)) {
    eriscv_mcu_mmio_write32(ERISCV_MCU_UART0_BASE + ERISCV_MCU_UART_TXDATA,
                         tx_buffer[tx_tail]);
    tx_tail = uart_ring_next(tx_tail, ERISCV_MCU_UART_ASYNC_TX_BUFFER_SIZE);
  }

  ctrl = eriscv_mcu_mmio_read32(ERISCV_MCU_UART0_BASE + ERISCV_MCU_UART_CTRL);
  if (tx_tail != tx_head) {
    ctrl |= ERISCV_MCU_UART_CTRL_TX_IRQ_EN;
  } else {
    ctrl &= ~ERISCV_MCU_UART_CTRL_TX_IRQ_EN;
  }
  eriscv_mcu_mmio_write32(ERISCV_MCU_UART0_BASE + ERISCV_MCU_UART_CTRL, ctrl);
}

static void uart_rx_service(void) {
  while ((eriscv_mcu_mmio_read32(ERISCV_MCU_UART0_BASE + ERISCV_MCU_UART_STATUS) &
          ERISCV_MCU_UART_STATUS_RX_VALID) != 0u) {
    eriscv_mcu_u32 next = uart_ring_next(rx_head, ERISCV_MCU_UART_ASYNC_RX_BUFFER_SIZE);
    eriscv_mcu_u32 value = eriscv_mcu_mmio_read32(ERISCV_MCU_UART0_BASE + ERISCV_MCU_UART_RXDATA);

    if (next == rx_tail) {
      rx_dropped++;
    } else {
      rx_buffer[rx_head] = value & 0xffu;
      rx_head = next;
    }
  }
}

void eriscv_mcu_uart_init(eriscv_mcu_u32 baud_divisor) {
  eriscv_mcu_mmio_write32(ERISCV_MCU_UART0_BASE + ERISCV_MCU_UART_BAUDDIV, baud_divisor);
  eriscv_mcu_mmio_write32(ERISCV_MCU_UART0_BASE + ERISCV_MCU_UART_CTRL,
                       ERISCV_MCU_UART_CTRL_TX_ENABLE | ERISCV_MCU_UART_CTRL_RX_ENABLE);
}

void eriscv_mcu_uart_putc(char ch) {
  while ((eriscv_mcu_mmio_read32(ERISCV_MCU_UART0_BASE + ERISCV_MCU_UART_STATUS) &
          ERISCV_MCU_UART_STATUS_TX_READY) == 0u) {
  }
  eriscv_mcu_mmio_write32(ERISCV_MCU_UART0_BASE + ERISCV_MCU_UART_TXDATA, (eriscv_mcu_u8)ch);
  while ((eriscv_mcu_mmio_read32(ERISCV_MCU_UART0_BASE + ERISCV_MCU_UART_STATUS) &
          ERISCV_MCU_UART_STATUS_TX_BUSY) == 0u) {
  }
}

void eriscv_mcu_uart_puts(const char *text) {
  while (*text != '\0') {
    if (*text == '\n') {
      eriscv_mcu_uart_putc('\r');
    }
    eriscv_mcu_uart_putc(*text++);
  }
}

int eriscv_mcu_uart_getc(void) {
  while ((eriscv_mcu_mmio_read32(ERISCV_MCU_UART0_BASE + ERISCV_MCU_UART_STATUS) &
          ERISCV_MCU_UART_STATUS_RX_VALID) == 0u) {
  }
  return (int)(eriscv_mcu_mmio_read32(ERISCV_MCU_UART0_BASE + ERISCV_MCU_UART_RXDATA) & 0xffu);
}

void eriscv_mcu_uart_async_init(eriscv_mcu_u32 baud_divisor) {
  eriscv_mcu_u32 state = uart_irq_save();

  tx_head = 0u;
  tx_tail = 0u;
  rx_head = 0u;
  rx_tail = 0u;
  rx_dropped = 0u;
  eriscv_mcu_uart_init(baud_divisor);
  eriscv_mcu_mmio_write32(ERISCV_MCU_UART0_BASE + ERISCV_MCU_UART_TX_WATERMARK,
                       ERISCV_MCU_UART_ASYNC_TX_WATERMARK);
  eriscv_mcu_mmio_write32(ERISCV_MCU_UART0_BASE + ERISCV_MCU_UART_RX_WATERMARK,
                       ERISCV_MCU_UART_ASYNC_RX_WATERMARK);
  eriscv_mcu_mmio_write32(ERISCV_MCU_UART0_BASE + ERISCV_MCU_UART_IRQ_STATUS,
                       ERISCV_MCU_UART_IRQ_RX_OVERRUN);
  eriscv_mcu_mmio_write32(ERISCV_MCU_UART0_BASE + ERISCV_MCU_UART_CTRL,
                       ERISCV_MCU_UART_CTRL_TX_ENABLE |
                       ERISCV_MCU_UART_CTRL_RX_ENABLE |
                       ERISCV_MCU_UART_CTRL_RX_IRQ_EN |
                       ERISCV_MCU_UART_CTRL_ERR_IRQ_EN);
  eriscv_mcu_plic_set_priority(ERISCV_MCU_UART0_PLIC_SOURCE, 1u);
  eriscv_mcu_plic_set_enabled(ERISCV_MCU_UART0_PLIC_SOURCE, 1);
  eriscv_mcu_plic_set_threshold(0u);
  eriscv_mcu_enable_machine_irqs(ERISCV_MCU_MIE_MEIE);

  uart_irq_restore(state);
}

int eriscv_mcu_uart_async_putc(char ch) {
  eriscv_mcu_u32 state = uart_irq_save();
  eriscv_mcu_u32 next = uart_ring_next(tx_head, ERISCV_MCU_UART_ASYNC_TX_BUFFER_SIZE);
  int accepted = 0;

  if (next != tx_tail) {
    tx_buffer[tx_head] = (eriscv_mcu_u8)ch;
    tx_head = next;
    __asm__ volatile ("fence rw, rw" ::: "memory");
    uart_tx_service();
    accepted = 1;
  }
  uart_irq_restore(state);
  return accepted;
}

eriscv_mcu_u32 eriscv_mcu_uart_async_write(const char *data, eriscv_mcu_u32 length) {
  eriscv_mcu_u32 written = 0u;
  eriscv_mcu_u32 state = uart_irq_save();

  while (written < length) {
    eriscv_mcu_u32 next = uart_ring_next(tx_head, ERISCV_MCU_UART_ASYNC_TX_BUFFER_SIZE);
    if (next == tx_tail) {
      break;
    }
    tx_buffer[tx_head] = uart_load_byte(data, written);
    tx_head = next;
    written++;
  }
  __asm__ volatile ("fence rw, rw" ::: "memory");
  uart_tx_service();
  uart_irq_restore(state);
  return written;
}

int eriscv_mcu_uart_async_getc(void) {
  int value = -1;
  eriscv_mcu_u32 state = uart_irq_save();

  if (rx_tail != rx_head) {
    value = (int)rx_buffer[rx_tail];
    rx_tail = uart_ring_next(rx_tail, ERISCV_MCU_UART_ASYNC_RX_BUFFER_SIZE);
  }
  uart_irq_restore(state);
  return value;
}

int eriscv_mcu_uart_async_tx_pending(void) {
  eriscv_mcu_u32 state = uart_irq_save();
  int pending = (tx_tail != tx_head) ||
                ((eriscv_mcu_mmio_read32(ERISCV_MCU_UART0_BASE + ERISCV_MCU_UART_STATUS) &
                  ERISCV_MCU_UART_STATUS_TX_BUSY) != 0u);

  uart_irq_restore(state);
  return pending;
}

eriscv_mcu_u32 eriscv_mcu_uart_async_rx_dropped(void) {
  eriscv_mcu_u32 state = uart_irq_save();
  eriscv_mcu_u32 dropped = rx_dropped;

  uart_irq_restore(state);
  return dropped;
}

void eriscv_mcu_uart_irq_handler(void) {
  eriscv_mcu_u32 irq_status = eriscv_mcu_mmio_read32(ERISCV_MCU_UART0_BASE + ERISCV_MCU_UART_IRQ_STATUS);

  if ((irq_status & ERISCV_MCU_UART_IRQ_RX_WATERMARK) != 0u) {
    uart_rx_service();
  }
  if ((irq_status & ERISCV_MCU_UART_IRQ_TX_WATERMARK) != 0u) {
    uart_tx_service();
  }
  if ((irq_status & ERISCV_MCU_UART_IRQ_RX_OVERRUN) != 0u) {
    eriscv_mcu_mmio_write32(ERISCV_MCU_UART0_BASE + ERISCV_MCU_UART_IRQ_STATUS,
                         ERISCV_MCU_UART_IRQ_RX_OVERRUN);
  }
}
