/* SPDX-License-Identifier: Apache-2.0 */
#define DT_DRV_COMPAT eriscv_wdt0
#include <errno.h>
#include <zephyr/device.h>
#include <zephyr/drivers/interrupt_controller/riscv_plic.h>
#include <zephyr/drivers/watchdog.h>
#include <zephyr/irq.h>
#include <zephyr/irq_multilevel.h>
#include <zephyr/sys/sys_io.h>

#define WDT_CTRL 0x00u
#define WDT_TIMEOUT 0x04u
#define WDT_WINDOW 0x08u
#define WDT_FEED 0x0cu
#define WDT_STATUS 0x10u
#define WDT_PRETIMEOUT 0x18u
#define WDT_FEED_MAGIC 0xacce55edu

struct eriscv_wdt_config { uintptr_t base; };
struct eriscv_wdt_data { wdt_callback_t callback; bool installed; bool running; };

static uint32_t wdt_cycles(uint32_t ms)
{
	return ms * (CONFIG_SYS_CLOCK_HW_CYCLES_PER_SEC / 1000u);
}

static int eriscv_wdt_install(const struct device *dev, const struct wdt_timeout_cfg *cfg)
{
	const struct eriscv_wdt_config *config = dev->config;
	struct eriscv_wdt_data *data = dev->data;
	if (data->running || data->installed || cfg->window.max == 0u || cfg->window.min != 0u) return -EINVAL;
	data->callback = cfg->callback;
	data->installed = true;
	sys_write32(wdt_cycles(cfg->window.max), config->base + WDT_TIMEOUT);
	sys_write32(cfg->callback ? wdt_cycles(cfg->window.max / 2u) : 0u,
		    config->base + WDT_PRETIMEOUT);
	return 0;
}
static int eriscv_wdt_setup(const struct device *dev, uint8_t options)
{
	const struct eriscv_wdt_config *config = dev->config;
	struct eriscv_wdt_data *data = dev->data;
	if (!data->installed || data->running || (options & ~WDT_OPT_PAUSE_HALTED_BY_DBG) != 0u) return -EINVAL;
	sys_write32(1u | (data->callback ? 4u : 0u), config->base + WDT_CTRL);
	data->running = true;
	return 0;
}
static int eriscv_wdt_disable(const struct device *dev)
{
	const struct eriscv_wdt_config *config = dev->config;
	struct eriscv_wdt_data *data = dev->data;
	if (!data->running) return -EFAULT;
	sys_write32(0, config->base + WDT_CTRL);
	data->running = data->installed = false;
	return 0;
}
static int eriscv_wdt_feed(const struct device *dev, int channel_id)
{
	const struct eriscv_wdt_config *config = dev->config;
	struct eriscv_wdt_data *data = dev->data;
	if (!data->running || channel_id != 0) return -EINVAL;
	sys_write32(WDT_FEED_MAGIC, config->base + WDT_FEED);
	return 0;
}
static void eriscv_wdt_isr(const struct device *dev)
{
	const struct eriscv_wdt_config *config = dev->config;
	struct eriscv_wdt_data *data = dev->data;
	sys_write32(8, config->base + WDT_STATUS);
	if (data->callback) data->callback(dev, 0);
}
static int eriscv_wdt_init(const struct device *dev)
{
	IRQ_CONNECT(DT_INST_IRQ(0, irq), DT_INST_IRQ(0, priority), eriscv_wdt_isr, DEVICE_DT_INST_GET(0), 0);
	riscv_plic_set_priority(IRQ_TO_L2(DT_INST_IRQ(0, irq)), DT_INST_IRQ(0, priority));
	irq_enable(IRQ_TO_L2(DT_INST_IRQ(0, irq)));
	return 0;
}
static const struct wdt_driver_api eriscv_wdt_api = { .setup = eriscv_wdt_setup, .disable = eriscv_wdt_disable, .install_timeout = eriscv_wdt_install, .feed = eriscv_wdt_feed };
static struct eriscv_wdt_data eriscv_wdt_data_0;
static const struct eriscv_wdt_config eriscv_wdt_config_0 = { .base = DT_INST_REG_ADDR(0) };
DEVICE_DT_INST_DEFINE(0, eriscv_wdt_init, NULL, &eriscv_wdt_data_0, &eriscv_wdt_config_0, POST_KERNEL, CONFIG_KERNEL_INIT_PRIORITY_DEVICE, &eriscv_wdt_api);
