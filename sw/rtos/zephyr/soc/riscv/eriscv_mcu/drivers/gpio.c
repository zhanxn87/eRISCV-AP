/*
 * eRISCV-MCU GPIO driver
 *
 * Copyright (c) 2024 eRISCV-MCU Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#define DT_DRV_COMPAT eriscv_gpio0

#include <errno.h>

#include <zephyr/device.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/gpio/gpio_utils.h>
#include <zephyr/irq.h>
#include <zephyr/sys/sys_io.h>
#include <zephyr/sys/util.h>

#define ERISCV_GPIO_OUT 0x00u
#define ERISCV_GPIO_IN  0x04u
#define ERISCV_GPIO_DIR 0x08u

struct eriscv_gpio_config {
	struct gpio_driver_config common;
	uintptr_t base;
};

static int eriscv_gpio_pin_configure(const struct device *dev, gpio_pin_t pin,
				     gpio_flags_t flags)
{
	const struct eriscv_gpio_config *config = dev->config;
	uint32_t bit;
	uint32_t value;

	if ((BIT(pin) & config->common.port_pin_mask) == 0u) {
		return -EINVAL;
	}
	if ((flags & (GPIO_SINGLE_ENDED | GPIO_PULL_UP | GPIO_PULL_DOWN)) != 0u) {
		return -ENOTSUP;
	}

	bit = BIT(pin);
	if ((flags & GPIO_OUTPUT_INIT_HIGH) != 0u) {
		value = sys_read32(config->base + ERISCV_GPIO_OUT) | bit;
		sys_write32(value, config->base + ERISCV_GPIO_OUT);
	} else if ((flags & GPIO_OUTPUT_INIT_LOW) != 0u) {
		value = sys_read32(config->base + ERISCV_GPIO_OUT) & ~bit;
		sys_write32(value, config->base + ERISCV_GPIO_OUT);
	}

	value = sys_read32(config->base + ERISCV_GPIO_DIR);
	if ((flags & GPIO_OUTPUT) != 0u) {
		value |= bit;
	} else {
		value &= ~bit;
	}
	sys_write32(value, config->base + ERISCV_GPIO_DIR);

	return 0;
}

static int eriscv_gpio_port_get_raw(const struct device *dev, gpio_port_value_t *value)
{
	const struct eriscv_gpio_config *config = dev->config;

	*value = sys_read32(config->base + ERISCV_GPIO_IN);
	return 0;
}

static int eriscv_gpio_port_set_masked_raw(const struct device *dev, gpio_port_pins_t mask,
					    gpio_port_value_t value)
{
	const struct eriscv_gpio_config *config = dev->config;
	unsigned int key;
	uint32_t output;

	mask &= config->common.port_pin_mask;
	key = irq_lock();
	output = sys_read32(config->base + ERISCV_GPIO_OUT);
	output = (output & ~mask) | (value & mask);
	sys_write32(output, config->base + ERISCV_GPIO_OUT);
	irq_unlock(key);

	return 0;
}

static int eriscv_gpio_port_set_bits_raw(const struct device *dev, gpio_port_pins_t mask)
{
	return eriscv_gpio_port_set_masked_raw(dev, mask, mask);
}

static int eriscv_gpio_port_clear_bits_raw(const struct device *dev, gpio_port_pins_t mask)
{
	return eriscv_gpio_port_set_masked_raw(dev, mask, 0u);
}

static int eriscv_gpio_port_toggle_bits(const struct device *dev, gpio_port_pins_t mask)
{
	const struct eriscv_gpio_config *config = dev->config;
	unsigned int key;
	uint32_t output;

	mask &= config->common.port_pin_mask;
	key = irq_lock();
	output = sys_read32(config->base + ERISCV_GPIO_OUT) ^ mask;
	sys_write32(output, config->base + ERISCV_GPIO_OUT);
	irq_unlock(key);

	return 0;
}

static int eriscv_gpio_pin_interrupt_configure(const struct device *dev, gpio_pin_t pin,
					       enum gpio_int_mode mode,
					       enum gpio_int_trig trig)
{
	ARG_UNUSED(dev);
	ARG_UNUSED(pin);
	ARG_UNUSED(mode);
	ARG_UNUSED(trig);

	return -ENOTSUP;
}

static const struct gpio_driver_api eriscv_gpio_driver_api = {
	.pin_configure = eriscv_gpio_pin_configure,
	.port_get_raw = eriscv_gpio_port_get_raw,
	.port_set_masked_raw = eriscv_gpio_port_set_masked_raw,
	.port_set_bits_raw = eriscv_gpio_port_set_bits_raw,
	.port_clear_bits_raw = eriscv_gpio_port_clear_bits_raw,
	.port_toggle_bits = eriscv_gpio_port_toggle_bits,
	.pin_interrupt_configure = eriscv_gpio_pin_interrupt_configure,
};

static int eriscv_gpio_init(const struct device *dev)
{
	ARG_UNUSED(dev);

	return 0;
}

#define ERISCV_GPIO_INIT(inst) \
	static struct gpio_driver_data eriscv_gpio_data_##inst; \
	static const struct eriscv_gpio_config eriscv_gpio_config_##inst = { \
		.common = { \
			.port_pin_mask = GPIO_PORT_PIN_MASK_FROM_DT_INST(inst), \
		}, \
		.base = DT_INST_REG_ADDR(inst), \
	}; \
	DEVICE_DT_INST_DEFINE(inst, eriscv_gpio_init, NULL, \
			      &eriscv_gpio_data_##inst, \
			      &eriscv_gpio_config_##inst, PRE_KERNEL_1, \
			      CONFIG_GPIO_INIT_PRIORITY, &eriscv_gpio_driver_api);

DT_INST_FOREACH_STATUS_OKAY(ERISCV_GPIO_INIT)
