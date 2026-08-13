/*
 * eRISCV-M2 Zephyr sample: multi-thread sync demo
 *
 * Demonstrates:
 *  - Two cooperative threads with semaphore handoff
 *  - UART printk output
 *  - Publish result word for ModelSim runner
 *
 * Copyright (c) 2024 eRISCV-MCU Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/kernel.h>
#include <zephyr/arch/cpu.h>
#include <zephyr/device.h>
#include <zephyr/drivers/counter.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/spi.h>
#include <zephyr/drivers/watchdog.h>
#include <zephyr/sys/atomic.h>
#include <zephyr/sys/printk.h>
#include <zephyr/sys/sys_io.h>

#define STACK_SIZE 1024
#define THREAD_A_PRIO 1
#define THREAD_B_PRIO 2
#define HANDOFF_COUNT  4
#define ZEPHYR_RESULT_PASS 0x5a6b7c8du
#define ERISCV_GPIO_OUT 0x00u
#define ERISCV_GPIO_DIR 0x08u

K_SEM_DEFINE(sem_a, 1, 1);
K_SEM_DEFINE(sem_b, 0, 1);
K_SEM_DEFINE(sem_done, 0, 1);
K_SEM_DEFINE(spi_done, 0, 1);
K_MUTEX_DEFINE(handoff_mutex);
K_MSGQ_DEFINE(handoff_msgq, sizeof(uint32_t), 1, 4);

/* Result word written to DTCM at a fixed symbol — sim runner reads this */
volatile unsigned int eriscv_zephyr_result __attribute__((section(".noinit")));

static atomic_t handoff_count;
static atomic_t timer_top_count;
static atomic_t wdt_pretimeout_count;
static atomic_t spi_result;
static uint32_t mutex_handoff;

extern uint32_t eriscv_uart_console_tx_irq_count(void);
extern bool eriscv_uart_console_tx_busy(void);

static int gpio_smoke_test(void)
{
	const struct device *gpio = DEVICE_DT_GET(DT_NODELABEL(gpio0));
	gpio_port_pins_t mask = BIT(0) | BIT(1) | BIT(2);

	if (!device_is_ready(gpio)) {
		return -ENODEV;
	}
	if (gpio_pin_configure(gpio, 0, GPIO_OUTPUT_LOW) != 0 ||
	    gpio_pin_configure(gpio, 1, GPIO_OUTPUT_LOW) != 0 ||
	    gpio_pin_configure(gpio, 2, GPIO_OUTPUT_LOW) != 0 ||
	    gpio_port_set_bits_raw(gpio, BIT(0) | BIT(2)) != 0 ||
	    gpio_port_clear_bits_raw(gpio, BIT(2)) != 0 ||
	    gpio_port_set_masked_raw(gpio, mask, BIT(0) | BIT(2)) != 0 ||
	    gpio_port_toggle_bits(gpio, BIT(0)) != 0 ||
	    gpio_port_toggle_bits(gpio, BIT(0)) != 0) {
		return -EIO;
	}
	if (sys_read32(DT_REG_ADDR(DT_NODELABEL(gpio0)) + ERISCV_GPIO_OUT) !=
	    (BIT(0) | BIT(2)) ||
	    sys_read32(DT_REG_ADDR(DT_NODELABEL(gpio0)) + ERISCV_GPIO_DIR) != mask) {
		return -EIO;
	}

	return 0;
}

static void timer_top_callback(const struct device *dev, void *user_data)
{
	ARG_UNUSED(dev);
	ARG_UNUSED(user_data);
	atomic_inc(&timer_top_count);
}

static int timer_smoke_test(void)
{
	const struct device *timer = DEVICE_DT_GET(DT_NODELABEL(timer0));
	struct counter_top_cfg top_cfg = {
		.ticks = counter_us_to_ticks(timer, 1000u),
		.callback = timer_top_callback,
	};

	if (!device_is_ready(timer) || counter_set_top_value(timer, &top_cfg) != 0) {
		return -EIO;
	}
	for (unsigned int wait_us = 0; wait_us < 10000u; ++wait_us) {
		if (atomic_get(&timer_top_count) != 0) {
			(void)counter_stop(timer);
			return 0;
		}
		k_busy_wait(1);
	}
	(void)counter_stop(timer);
	return -ETIMEDOUT;
}

static void wdt_pretimeout_callback(const struct device *dev, int channel_id)
{
	ARG_UNUSED(dev);
	ARG_UNUSED(channel_id);
	atomic_inc(&wdt_pretimeout_count);
}

static int wdt_smoke_test(void)
{
	const struct device *wdt = DEVICE_DT_GET(DT_NODELABEL(wdt0));
	struct wdt_timeout_cfg timeout_cfg = {
		.window = { .min = 0u, .max = 2u },
		.callback = wdt_pretimeout_callback,
	};
	int channel_id;

	if (!device_is_ready(wdt) ||
	    (channel_id = wdt_install_timeout(wdt, &timeout_cfg)) < 0 ||
	    wdt_setup(wdt, 0u) != 0) {
		return -EIO;
	}
	for (unsigned int wait_us = 0; wait_us < 1500u; ++wait_us) {
		if (atomic_get(&wdt_pretimeout_count) != 0) {
			return wdt_feed(wdt, channel_id) == 0 && wdt_disable(wdt) == 0 ? 0 : -EIO;
		}
		k_busy_wait(1);
	}
	(void)wdt_disable(wdt);
	return -ETIMEDOUT;
}

static void spi_callback(const struct device *dev, int result, void *user_data)
{
	ARG_UNUSED(dev);
	ARG_UNUSED(user_data);
	atomic_set(&spi_result, result);
	k_sem_give(&spi_done);
}

static int spi_smoke_test(void)
{
	const struct device *spi = DEVICE_DT_GET(DT_NODELABEL(spi0));
	const uint8_t tx_data = 0xa5u;
	uint8_t rx_data = 0u;
	const struct spi_buf tx_buf = { .buf = (void *)&tx_data, .len = 1u };
	const struct spi_buf rx_buf = { .buf = &rx_data, .len = 1u };
	const struct spi_buf_set tx = { .buffers = &tx_buf, .count = 1u };
	const struct spi_buf_set rx = { .buffers = &rx_buf, .count = 1u };
	const struct spi_config config = {
		.frequency = 1000000u,
		.operation = SPI_OP_MODE_MASTER | SPI_WORD_SET(8),
		.slave = 0u,
	};

	atomic_set(&spi_result, -EINPROGRESS);
	if (!device_is_ready(spi) ||
	    spi_transceive_cb(spi, &config, &tx, &rx, spi_callback, NULL) != 0 ||
	    k_sem_take(&spi_done, K_MSEC(10)) != 0 ||
	    atomic_get(&spi_result) != 0 || rx_data != 0x3cu) {
		return -EIO;
	}
	return 0;
}

/* ---- Thread A: takes sem_a, prints, gives sem_b ---- */
static void thread_a_entry(void *p1, void *p2, void *p3)
{
	ARG_UNUSED(p1);
	ARG_UNUSED(p2);
	ARG_UNUSED(p3);

	for (unsigned int handoff = 0; handoff < HANDOFF_COUNT; ++handoff) {
		uint32_t message = handoff + 1u;

		if (k_sem_take(&sem_a, K_FOREVER) != 0) {
			eriscv_zephyr_result = 0xdead0001u;
			return;
		}
		if (k_mutex_lock(&handoff_mutex, K_FOREVER) != 0) {
			eriscv_zephyr_result = 0xdead000au;
			return;
		}
		mutex_handoff = message;
		if (k_mutex_unlock(&handoff_mutex) != 0 ||
		    k_msgq_put(&handoff_msgq, &message, K_NO_WAIT) != 0) {
			eriscv_zephyr_result = 0xdead000bu;
			return;
		}
		printk("Zephyr-A: handoff %u\n", handoff + 1);
		atomic_inc(&handoff_count);
		k_sem_give(&sem_b);
	}

	printk("Zephyr-A: done\n");
}

/* ---- Thread B: takes sem_b, prints, gives sem_a ---- */
static void thread_b_entry(void *p1, void *p2, void *p3)
{
	ARG_UNUSED(p1);
	ARG_UNUSED(p2);
	ARG_UNUSED(p3);

	for (unsigned int handoff = 0; handoff < HANDOFF_COUNT; ++handoff) {
		uint32_t message;

		if (k_sem_take(&sem_b, K_FOREVER) != 0) {
			eriscv_zephyr_result = 0xdead0002u;
			return;
		}
		if (k_mutex_lock(&handoff_mutex, K_FOREVER) != 0 ||
		    mutex_handoff != handoff + 1u ||
		    k_mutex_unlock(&handoff_mutex) != 0 ||
		    k_msgq_get(&handoff_msgq, &message, K_NO_WAIT) != 0 ||
		    message != handoff + 1u) {
			eriscv_zephyr_result = 0xdead000cu;
			return;
		}
		printk("Zephyr-B: handoff %u\n", handoff + 1);
		k_sem_give(&sem_a);
	}

	printk("Zephyr-B: done\n");
	k_sem_give(&sem_done);
}

K_THREAD_DEFINE(thread_a, STACK_SIZE,
		thread_a_entry, NULL, NULL, NULL,
		THREAD_A_PRIO, 0, 0);

K_THREAD_DEFINE(thread_b, STACK_SIZE,
		thread_b_entry, NULL, NULL, NULL,
		THREAD_B_PRIO, 0, 0);

/* ---- Main thread: waits for completion, publishes result ---- */
int main(void)
{
	printk("Zephyr eRISCV-M2 multi-thread demo\n");
	if (gpio_smoke_test() != 0) {
		printk("Zephyr FAIL: GPIO smoke\n");
		eriscv_zephyr_result = 0xdead0006u;
		return 0;
	}
	if (timer_smoke_test() != 0) {
		printk("Zephyr FAIL: timer smoke\n");
		eriscv_zephyr_result = 0xdead0007u;
		return 0;
	}
	if (wdt_smoke_test() != 0) {
		printk("Zephyr FAIL: WDT smoke\n");
		eriscv_zephyr_result = 0xdead0008u;
		return 0;
	}
	if (spi_smoke_test() != 0) {
		printk("Zephyr FAIL: SPI smoke\n");
		eriscv_zephyr_result = 0xdead0009u;
		return 0;
	}
	for (unsigned int wait_ms = 0; wait_ms < 100; ++wait_ms) {
		if (eriscv_uart_console_tx_irq_count() != 0u &&
		    !eriscv_uart_console_tx_busy()) {
			break;
		}
		k_msleep(1);
	}
	if (eriscv_uart_console_tx_irq_count() == 0u ||
	    eriscv_uart_console_tx_busy()) {
		printk("Zephyr FAIL: UART IRQ smoke\n");
		eriscv_zephyr_result = 0xdead0005u;
		return 0;
	}

	if (k_sem_take(&sem_done, K_MSEC(100)) == 0 &&
	    atomic_get(&handoff_count) == HANDOFF_COUNT) {
		printk("Zephyr PASS: all handoffs complete\n");
		eriscv_zephyr_result = ZEPHYR_RESULT_PASS;
	} else {
		printk("Zephyr FAIL: handoff timeout\n");
		eriscv_zephyr_result = 0xdead0003u;
	}

	return 0;
}
