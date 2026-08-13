/* SPDX-License-Identifier: Apache-2.0 */

#define DT_DRV_COMPAT eriscv_spi0

#include <errno.h>

#include <zephyr/device.h>
#include <zephyr/drivers/interrupt_controller/riscv_plic.h>
#include <zephyr/drivers/spi.h>
#include <zephyr/irq.h>
#include <zephyr/irq_multilevel.h>
#include <zephyr/sys/sys_io.h>
#include <zephyr/sys/util.h>

#define ERISCV_SPI_TXDATA 0x00u
#define ERISCV_SPI_RXDATA 0x04u
#define ERISCV_SPI_STATUS 0x08u
#define ERISCV_SPI_CLKDIV 0x0cu
#define ERISCV_SPI_CTRL   0x10u
#define ERISCV_SPI_SS     0x14u

#define ERISCV_SPI_CTRL_ENABLE BIT(0)
#define ERISCV_SPI_CTRL_IRQ    BIT(1)
#define ERISCV_SPI_CTRL_CPOL   BIT(2)
#define ERISCV_SPI_CTRL_CPHA   BIT(3)
#define ERISCV_SPI_CTRL_DONE   BIT(4)
#define ERISCV_SPI_CTRL_LSB    BIT(5)
#define ERISCV_SPI_STATUS_BUSY BIT(1)
#define ERISCV_SPI_STATUS_DONE BIT(3)


struct eriscv_spi_config {
	uintptr_t base;
};

struct eriscv_spi_data {
	const struct spi_buf_set *tx_bufs;
	const struct spi_buf_set *rx_bufs;
	size_t len;
	size_t index;
	uint32_t ctrl;
	spi_callback_t callback;
	void *userdata;
	bool active;
};

static int eriscv_spi_validate(const struct spi_config *config)
{
	if (SPI_OP_MODE_GET(config->operation) != SPI_OP_MODE_MASTER ||
	    SPI_WORD_SIZE_GET(config->operation) != 8u ||
	    (config->operation & (SPI_MODE_LOOP | SPI_CS_ACTIVE_HIGH)) != 0u ||
	    spi_cs_is_gpio(config) || config->frequency == 0u || config->slave >= 4u) {
		return -ENOTSUP;
	}
	return 0;
}

static uint8_t eriscv_spi_tx_byte(const struct spi_buf_set *tx, size_t index)
{
	size_t offset = index;

	if (tx == NULL) {
		return 0xffu;
	}
	for (size_t i = 0; i < tx->count; ++i) {
		if (offset < tx->buffers[i].len) {
			return ((const uint8_t *)tx->buffers[i].buf)[offset];
		}
		offset -= tx->buffers[i].len;
	}
	return 0xffu;
}

static void eriscv_spi_rx_byte(const struct spi_buf_set *rx, size_t index, uint8_t value)
{
	size_t offset = index;

	if (rx == NULL) {
		return;
	}
	for (size_t i = 0; i < rx->count; ++i) {
		if (offset < rx->buffers[i].len) {
			((uint8_t *)rx->buffers[i].buf)[offset] = value;
			return;
		}
		offset -= rx->buffers[i].len;
	}
}

static size_t eriscv_spi_len(const struct spi_buf_set *bufs)
{
	size_t len = 0u;

	if (bufs != NULL) {
		for (size_t i = 0; i < bufs->count; ++i) {
			len += bufs->buffers[i].len;
		}
	}
	return len;
}

static uint32_t eriscv_spi_ctrl(const struct spi_config *config, bool irq)
{
	uint32_t ctrl = ERISCV_SPI_CTRL_ENABLE;

	if (irq) {
		ctrl |= ERISCV_SPI_CTRL_IRQ;
	}
	if ((config->operation & SPI_MODE_CPOL) != 0u) {
		ctrl |= ERISCV_SPI_CTRL_CPOL;
	}
	if ((config->operation & SPI_MODE_CPHA) != 0u) {
		ctrl |= ERISCV_SPI_CTRL_CPHA;
	}
	if ((config->operation & SPI_TRANSFER_LSB) != 0u) {
		ctrl |= ERISCV_SPI_CTRL_LSB;
	}
	return ctrl;
}

static uint32_t eriscv_spi_divisor(const struct spi_config *config)
{
	return MAX(DIV_ROUND_UP(CONFIG_SYS_CLOCK_HW_CYCLES_PER_SEC,
				2u * config->frequency), 1u);
}

static int eriscv_spi_transceive(const struct device *dev,
				 const struct spi_config *config,
				 const struct spi_buf_set *tx_bufs,
				 const struct spi_buf_set *rx_bufs)
{
	const struct eriscv_spi_config *cfg = dev->config;
	struct eriscv_spi_data *data = dev->data;
	size_t len = MAX(eriscv_spi_len(tx_bufs), eriscv_spi_len(rx_bufs));
	uint32_t divisor;
	uint32_t ctrl;
	unsigned int key;

	if (eriscv_spi_validate(config) != 0 || len == 0u) {
		return -EINVAL;
	}
	key = irq_lock();
	if (data->active) {
		irq_unlock(key);
		return -EBUSY;
	}
	irq_unlock(key);
	divisor = eriscv_spi_divisor(config);
	ctrl = eriscv_spi_ctrl(config, false);

	sys_write32(divisor, cfg->base + ERISCV_SPI_CLKDIV);
	sys_write32(ctrl, cfg->base + ERISCV_SPI_CTRL);
	sys_write32(~BIT(config->slave) & 0xfu, cfg->base + ERISCV_SPI_SS);
	for (size_t i = 0; i < len; ++i) {
		uint32_t timeout = divisor * 32u + 1000u;

		sys_write32(eriscv_spi_tx_byte(tx_bufs, i), cfg->base + ERISCV_SPI_TXDATA);
		while ((sys_read32(cfg->base + ERISCV_SPI_STATUS) & ERISCV_SPI_STATUS_BUSY) != 0u) {
			if (timeout-- == 0u) {
				sys_write32(0xfu, cfg->base + ERISCV_SPI_SS);
				return -ETIMEDOUT;
			}
		}
		eriscv_spi_rx_byte(rx_bufs, i,
			(uint8_t)sys_read32(cfg->base + ERISCV_SPI_RXDATA));
	}
	sys_write32(0xfu, cfg->base + ERISCV_SPI_SS);
	return 0;
}

static void eriscv_spi_complete(const struct device *dev, int result)
{
	const struct eriscv_spi_config *cfg = dev->config;
	struct eriscv_spi_data *data = dev->data;
	spi_callback_t callback = data->callback;
	void *userdata = data->userdata;

	sys_write32(0xfu, cfg->base + ERISCV_SPI_SS);
	data->active = false;
	data->callback = NULL;
	data->userdata = NULL;
	if (callback != NULL) {
		callback(dev, result, userdata);
	}
}

static void eriscv_spi_isr(const struct device *dev)
{
	const struct eriscv_spi_config *cfg = dev->config;
	struct eriscv_spi_data *data = dev->data;

	if (!data->active ||
	    (sys_read32(cfg->base + ERISCV_SPI_STATUS) & ERISCV_SPI_STATUS_DONE) == 0u) {
		return;
	}
	sys_write32(data->ctrl | ERISCV_SPI_CTRL_DONE, cfg->base + ERISCV_SPI_CTRL);
	eriscv_spi_rx_byte(data->rx_bufs, data->index,
		(uint8_t)sys_read32(cfg->base + ERISCV_SPI_RXDATA));
	data->index++;
	if (data->index == data->len) {
		eriscv_spi_complete(dev, 0);
		return;
	}
	sys_write32(eriscv_spi_tx_byte(data->tx_bufs, data->index),
		    cfg->base + ERISCV_SPI_TXDATA);
}

#ifdef CONFIG_SPI_ASYNC
static int eriscv_spi_transceive_async(const struct device *dev,
				       const struct spi_config *config,
				       const struct spi_buf_set *tx_bufs,
				       const struct spi_buf_set *rx_bufs,
				       spi_callback_t callback, void *userdata)
{
	const struct eriscv_spi_config *cfg = dev->config;
	struct eriscv_spi_data *data = dev->data;
	size_t len = MAX(eriscv_spi_len(tx_bufs), eriscv_spi_len(rx_bufs));
	unsigned int key;

	if (eriscv_spi_validate(config) != 0 || len == 0u) {
		return -EINVAL;
	}
	key = irq_lock();
	if (data->active) {
		irq_unlock(key);
		return -EBUSY;
	}
	data->tx_bufs = tx_bufs;
	data->rx_bufs = rx_bufs;
	data->len = len;
	data->index = 0u;
	data->ctrl = eriscv_spi_ctrl(config, true);
	data->callback = callback;
	data->userdata = userdata;
	data->active = true;
	sys_write32(eriscv_spi_divisor(config), cfg->base + ERISCV_SPI_CLKDIV);
	sys_write32(data->ctrl, cfg->base + ERISCV_SPI_CTRL);
	sys_write32(~BIT(config->slave) & 0xfu, cfg->base + ERISCV_SPI_SS);
	sys_write32(eriscv_spi_tx_byte(tx_bufs, 0u), cfg->base + ERISCV_SPI_TXDATA);
	irq_unlock(key);
	return 0;
}
#endif

static int eriscv_spi_init(const struct device *dev)
{
	const struct eriscv_spi_config *cfg = dev->config;

	sys_write32(ERISCV_SPI_CTRL_ENABLE, cfg->base + ERISCV_SPI_CTRL);
	sys_write32(0xfu, cfg->base + ERISCV_SPI_SS);
	return 0;
}

static const struct spi_driver_api eriscv_spi_api = {
	.transceive = eriscv_spi_transceive,
#ifdef CONFIG_SPI_ASYNC
	.transceive_async = eriscv_spi_transceive_async,
#endif
};

#define ERISCV_SPI_INIT(inst) \
	static struct eriscv_spi_data eriscv_spi_data_##inst; \
	static const struct eriscv_spi_config eriscv_spi_config_##inst = { \
		.base = DT_INST_REG_ADDR(inst), \
	}; \
	static int eriscv_spi_init_##inst(const struct device *dev) \
	{ \
		int ret = eriscv_spi_init(dev); \
		IRQ_CONNECT(DT_INST_IRQ(inst, irq), DT_INST_IRQ(inst, priority), \
			eriscv_spi_isr, DEVICE_DT_INST_GET(inst), 0); \
		riscv_plic_set_priority(IRQ_TO_L2(DT_INST_IRQ(inst, irq)), \
			DT_INST_IRQ(inst, priority)); \
		irq_enable(IRQ_TO_L2(DT_INST_IRQ(inst, irq))); \
		return ret; \
	} \
	DEVICE_DT_INST_DEFINE(inst, eriscv_spi_init_##inst, NULL, &eriscv_spi_data_##inst, \
			      &eriscv_spi_config_##inst, POST_KERNEL, \
			      CONFIG_SPI_INIT_PRIORITY, &eriscv_spi_api);

DT_INST_FOREACH_STATUS_OKAY(ERISCV_SPI_INIT)
