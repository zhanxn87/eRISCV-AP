/* SPDX-License-Identifier: Apache-2.0 */

#define DT_DRV_COMPAT eriscv_timer0

#include <errno.h>

#include <zephyr/device.h>
#include <zephyr/drivers/counter.h>
#include <zephyr/drivers/interrupt_controller/riscv_plic.h>
#include <zephyr/irq.h>
#include <zephyr/irq_multilevel.h>
#include <zephyr/sys/sys_io.h>

#define ERISCV_TIMER_CTRL 0x00u
#define ERISCV_TIMER_COUNT 0x04u
#define ERISCV_TIMER_COMPARE 0x08u
#define ERISCV_TIMER_STATUS 0x0cu
#define ERISCV_TIMER_ENABLE BIT(0)
#define ERISCV_TIMER_IRQ_ENABLE BIT(1)

struct eriscv_timer_config {
	struct counter_config_info info;
	uintptr_t base;
};

struct eriscv_timer_data {
	counter_top_callback_t callback;
	void *user_data;
};

static int eriscv_timer_start(const struct device *dev)
{
	const struct eriscv_timer_config *config = dev->config;
	sys_write32(sys_read32(config->base + ERISCV_TIMER_CTRL) | ERISCV_TIMER_ENABLE,
		    config->base + ERISCV_TIMER_CTRL);
	return 0;
}

static int eriscv_timer_stop(const struct device *dev)
{
	const struct eriscv_timer_config *config = dev->config;
	sys_write32(0, config->base + ERISCV_TIMER_CTRL);
	return 0;
}

static int eriscv_timer_get_value(const struct device *dev, uint32_t *ticks)
{
	const struct eriscv_timer_config *config = dev->config;
	*ticks = sys_read32(config->base + ERISCV_TIMER_COUNT);
	return 0;
}

static int eriscv_timer_set_top_value(const struct device *dev,
				      const struct counter_top_cfg *cfg)
{
	const struct eriscv_timer_config *config = dev->config;
	struct eriscv_timer_data *data = dev->data;

	if (cfg->ticks == 0u || (cfg->flags & COUNTER_TOP_CFG_DONT_RESET) != 0u) {
		return -ENOTSUP;
	}
	data->callback = cfg->callback;
	data->user_data = cfg->user_data;
	sys_write32(cfg->ticks, config->base + ERISCV_TIMER_COMPARE);
	sys_write32(0, config->base + ERISCV_TIMER_COUNT);
	sys_write32(ERISCV_TIMER_ENABLE | (cfg->callback != NULL ? ERISCV_TIMER_IRQ_ENABLE : 0u),
		    config->base + ERISCV_TIMER_CTRL);
	return 0;
}

static uint32_t eriscv_timer_get_pending_int(const struct device *dev)
{
	const struct eriscv_timer_config *config = dev->config;
	return sys_read32(config->base + ERISCV_TIMER_STATUS) & 1u;
}

static uint32_t eriscv_timer_get_top_value(const struct device *dev)
{
	const struct eriscv_timer_config *config = dev->config;
	return sys_read32(config->base + ERISCV_TIMER_COMPARE);
}

static void eriscv_timer_isr(const struct device *dev)
{
	const struct eriscv_timer_config *config = dev->config;
	struct eriscv_timer_data *data = dev->data;

	sys_write32(1, config->base + ERISCV_TIMER_STATUS);
	sys_write32(0, config->base + ERISCV_TIMER_COUNT);
	if (data->callback != NULL) {
		data->callback(dev, data->user_data);
	}
}

static int eriscv_timer_init(const struct device *dev)
{
	const struct eriscv_timer_config *config = dev->config;

	IRQ_CONNECT(DT_INST_IRQ(0, irq), DT_INST_IRQ(0, priority), eriscv_timer_isr,
		    DEVICE_DT_INST_GET(0), 0);
	riscv_plic_set_priority(IRQ_TO_L2(DT_INST_IRQ(0, irq)), DT_INST_IRQ(0, priority));
	irq_enable(IRQ_TO_L2(DT_INST_IRQ(0, irq)));
	sys_write32(0, config->base + ERISCV_TIMER_CTRL);
	sys_write32(1, config->base + ERISCV_TIMER_STATUS);
	return 0;
}

static const struct counter_driver_api eriscv_timer_api = {
	.start = eriscv_timer_start, .stop = eriscv_timer_stop,
	.get_value = eriscv_timer_get_value, .set_top_value = eriscv_timer_set_top_value,
	.get_pending_int = eriscv_timer_get_pending_int,
	.get_top_value = eriscv_timer_get_top_value,
};

static struct eriscv_timer_data eriscv_timer_data_0;
static const struct eriscv_timer_config eriscv_timer_config_0 = {
	.info = { .max_top_value = UINT32_MAX, .freq = CONFIG_SYS_CLOCK_HW_CYCLES_PER_SEC,
		  .flags = COUNTER_CONFIG_INFO_COUNT_UP, .channels = 0u },
	.base = DT_INST_REG_ADDR(0),
};

DEVICE_DT_INST_DEFINE(0, eriscv_timer_init, NULL, &eriscv_timer_data_0,
		      &eriscv_timer_config_0, POST_KERNEL, CONFIG_COUNTER_INIT_PRIORITY,
		      &eriscv_timer_api);
