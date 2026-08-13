/* SPDX-License-Identifier: Apache-2.0 */

#include <zephyr/device.h>
#include <zephyr/drivers/uart.h>
#include <zephyr/init.h>
#include <zephyr/irq.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>
#include <zephyr/sys/ring_buffer.h>

extern void __printk_hook_install(int (*fn)(int c));

#define ERISCV_UART_IRQ_CONSOLE_TX_BUFFER_SIZE 256u

static const struct device *const uart_console_dev =
	DEVICE_DT_GET(DT_CHOSEN(zephyr_console));

static uint8_t uart_console_tx_ring_data[ERISCV_UART_IRQ_CONSOLE_TX_BUFFER_SIZE];
static struct ring_buf uart_console_tx_ring;

static volatile uint32_t uart_console_tx_irq_count;
static volatile uint32_t uart_console_tx_dropped;

static void uart_console_tx_drain(const struct device *dev)
{
	uint8_t c;

	while (uart_irq_tx_ready(dev)) {
		if (ring_buf_get(&uart_console_tx_ring, &c, 1) == 0u) {
			uart_irq_tx_disable(dev);
			return;
		}
		(void)uart_fifo_fill(dev, &c, 1);
	}
}

static void uart_console_irq_callback(const struct device *dev, void *user_data)
{
	ARG_UNUSED(user_data);

	if (!uart_irq_update(dev) || !uart_irq_is_pending(dev)) {
		return;
	}
	if (uart_irq_tx_ready(dev)) {
		uart_console_tx_irq_count++;
		uart_console_tx_drain(dev);
	}
	if (uart_err_check(dev) != 0) {
		/* RX is not enabled by the TX-only console backend. */
	}
}

static void uart_console_enqueue(uint8_t c)
{
	if (ring_buf_put(&uart_console_tx_ring, &c, 1) == 0u) {
		uart_console_tx_dropped++;
	}
}

static int uart_console_out(int c)
{
	unsigned int key = irq_lock();

	if (c == '\n') {
		uart_console_enqueue('\r');
	}
	uart_console_enqueue((uint8_t)c);
	uart_irq_tx_enable(uart_console_dev);
	irq_unlock(key);

	return c;
}

uint32_t eriscv_uart_console_tx_irq_count(void)
{
	return uart_console_tx_irq_count;
}

bool eriscv_uart_console_tx_busy(void)
{
	unsigned int key = irq_lock();
	bool busy = ring_buf_size_get(&uart_console_tx_ring) != 0u ||
		    uart_irq_tx_complete(uart_console_dev) == 0;

	irq_unlock(key);
	return busy;
}

static int eriscv_uart_irq_console_init(void)
{
	if (!device_is_ready(uart_console_dev)) {
		return -ENODEV;
	}

	ring_buf_init(&uart_console_tx_ring, sizeof(uart_console_tx_ring_data),
		      uart_console_tx_ring_data);
	uart_irq_callback_user_data_set(uart_console_dev, uart_console_irq_callback, NULL);
	__printk_hook_install(uart_console_out);

	return 0;
}

SYS_INIT(eriscv_uart_irq_console_init, POST_KERNEL, 61);
