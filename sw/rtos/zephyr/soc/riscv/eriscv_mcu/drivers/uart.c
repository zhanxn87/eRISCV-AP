/* SPDX-License-Identifier: Apache-2.0 */

#define DT_DRV_COMPAT eriscv_uart0

#include <zephyr/device.h>
#include <zephyr/arch/cpu.h>
#include <zephyr/drivers/uart.h>
#include <zephyr/drivers/interrupt_controller/riscv_plic.h>
#include <zephyr/init.h>
#include <zephyr/irq.h>
#include <zephyr/irq_multilevel.h>
#include <zephyr/sys/sys_io.h>

#define ERISCV_UART_TXDATA       0x00u
#define ERISCV_UART_RXDATA       0x04u
#define ERISCV_UART_STATUS       0x08u
#define ERISCV_UART_BAUDDIV      0x0cu
#define ERISCV_UART_CTRL         0x10u
#define ERISCV_UART_IRQ_STATUS   0x1cu

#define ERISCV_UART_TX_READY     BIT(0)
#define ERISCV_UART_RX_VALID     BIT(1)
#define ERISCV_UART_TX_BUSY      BIT(2)
#define ERISCV_UART_RX_OVERRUN   BIT(3)
#define ERISCV_UART_TX_ENABLE    BIT(0)
#define ERISCV_UART_RX_ENABLE    BIT(1)
#define ERISCV_UART_RX_IRQ_ENABLE BIT(2)
#define ERISCV_UART_TX_IRQ_ENABLE BIT(3)
#define ERISCV_UART_ERR_IRQ_ENABLE BIT(4)
#define ERISCV_UART_IRQ_RX_WATERMARK BIT(0)
#define ERISCV_UART_IRQ_TX_WATERMARK BIT(1)
#define ERISCV_UART_IRQ_RX_OVERRUN BIT(2)

struct eriscv_uart_config {
	uintptr_t base;
	uint32_t baud_divisor;
#ifdef CONFIG_UART_INTERRUPT_DRIVEN
	void (*irq_config_func)(const struct device *dev);
#endif
};

struct eriscv_uart_data {
	uart_irq_callback_user_data_t callback;
	void *callback_data;
};

#ifdef CONFIG_UART_INTERRUPT_DRIVEN
static void eriscv_uart_ctrl_update(const struct eriscv_uart_config *config,
				   uint32_t set, uint32_t clear)
{
	uint32_t ctrl = sys_read32(config->base + ERISCV_UART_CTRL);

	ctrl = (ctrl | set) & ~clear;
	sys_write32(ctrl, config->base + ERISCV_UART_CTRL);
}
#endif

static int eriscv_uart_poll_in(const struct device *dev, unsigned char *c)
{
	const struct eriscv_uart_config *config = dev->config;

	if ((sys_read32(config->base + ERISCV_UART_STATUS) & ERISCV_UART_RX_VALID) == 0u) {
		return -1;
	}
	*c = (unsigned char)sys_read32(config->base + ERISCV_UART_RXDATA);
	return 0;
}

static void eriscv_uart_poll_out(const struct device *dev, unsigned char c)
{
	const struct eriscv_uart_config *config = dev->config;

	while ((sys_read32(config->base + ERISCV_UART_STATUS) & ERISCV_UART_TX_READY) == 0u) {
	}
	sys_write32(c, config->base + ERISCV_UART_TXDATA);
	while ((sys_read32(config->base + ERISCV_UART_STATUS) & ERISCV_UART_TX_BUSY) == 0u) {
	}
}

static int eriscv_uart_err_check(const struct device *dev)
{
	const struct eriscv_uart_config *config = dev->config;

	if ((sys_read32(config->base + ERISCV_UART_STATUS) & ERISCV_UART_RX_OVERRUN) == 0u) {
		return 0;
	}
	sys_write32(ERISCV_UART_IRQ_RX_OVERRUN, config->base + ERISCV_UART_IRQ_STATUS);
	return UART_ERROR_OVERRUN;
}

#ifdef CONFIG_UART_INTERRUPT_DRIVEN
static int eriscv_uart_fifo_fill(const struct device *dev, const uint8_t *tx_data,
				 int len)
{
	const struct eriscv_uart_config *config = dev->config;
	int count = 0;

	while (count < len &&
	       (sys_read32(config->base + ERISCV_UART_STATUS) & ERISCV_UART_TX_READY) != 0u) {
		sys_write32(tx_data[count++], config->base + ERISCV_UART_TXDATA);
	}
	return count;
}

static int eriscv_uart_fifo_read(const struct device *dev, uint8_t *rx_data,
				 const int size)
{
	const struct eriscv_uart_config *config = dev->config;
	int count = 0;

	while (count < size &&
	       (sys_read32(config->base + ERISCV_UART_STATUS) & ERISCV_UART_RX_VALID) != 0u) {
		rx_data[count++] = (uint8_t)sys_read32(config->base + ERISCV_UART_RXDATA);
	}
	return count;
}

static void eriscv_uart_irq_tx_enable(const struct device *dev)
{
	const struct eriscv_uart_config *config = dev->config;

	eriscv_uart_ctrl_update(config, ERISCV_UART_TX_IRQ_ENABLE, 0u);
}

static void eriscv_uart_irq_tx_disable(const struct device *dev)
{
	const struct eriscv_uart_config *config = dev->config;

	eriscv_uart_ctrl_update(config, 0u, ERISCV_UART_TX_IRQ_ENABLE);
}

static int eriscv_uart_irq_tx_ready(const struct device *dev)
{
	const struct eriscv_uart_config *config = dev->config;
	uint32_t ctrl = sys_read32(config->base + ERISCV_UART_CTRL);
	uint32_t status = sys_read32(config->base + ERISCV_UART_STATUS);

	return (ctrl & ERISCV_UART_TX_IRQ_ENABLE) != 0u &&
	       (status & ERISCV_UART_TX_READY) != 0u;
}

static void eriscv_uart_irq_rx_enable(const struct device *dev)
{
	const struct eriscv_uart_config *config = dev->config;

	eriscv_uart_ctrl_update(config, ERISCV_UART_RX_IRQ_ENABLE, 0u);
}

static void eriscv_uart_irq_rx_disable(const struct device *dev)
{
	const struct eriscv_uart_config *config = dev->config;

	eriscv_uart_ctrl_update(config, 0u, ERISCV_UART_RX_IRQ_ENABLE);
}

static int eriscv_uart_irq_tx_complete(const struct device *dev)
{
	const struct eriscv_uart_config *config = dev->config;

	return (sys_read32(config->base + ERISCV_UART_STATUS) & ERISCV_UART_TX_BUSY) == 0u;
}

static int eriscv_uart_irq_rx_ready(const struct device *dev)
{
	const struct eriscv_uart_config *config = dev->config;
	uint32_t ctrl = sys_read32(config->base + ERISCV_UART_CTRL);
	uint32_t status = sys_read32(config->base + ERISCV_UART_STATUS);

	return (ctrl & ERISCV_UART_RX_IRQ_ENABLE) != 0u &&
	       (status & ERISCV_UART_RX_VALID) != 0u;
}

static void eriscv_uart_irq_err_enable(const struct device *dev)
{
	const struct eriscv_uart_config *config = dev->config;

	eriscv_uart_ctrl_update(config, ERISCV_UART_ERR_IRQ_ENABLE, 0u);
}

static void eriscv_uart_irq_err_disable(const struct device *dev)
{
	const struct eriscv_uart_config *config = dev->config;

	eriscv_uart_ctrl_update(config, 0u, ERISCV_UART_ERR_IRQ_ENABLE);
}

static int eriscv_uart_irq_is_pending(const struct device *dev)
{
	const struct eriscv_uart_config *config = dev->config;
	uint32_t ctrl = sys_read32(config->base + ERISCV_UART_CTRL);
	uint32_t pending = sys_read32(config->base + ERISCV_UART_IRQ_STATUS);

	return ((ctrl & ERISCV_UART_RX_IRQ_ENABLE) != 0u &&
		(pending & ERISCV_UART_IRQ_RX_WATERMARK) != 0u) ||
	       ((ctrl & ERISCV_UART_TX_IRQ_ENABLE) != 0u &&
		(pending & ERISCV_UART_IRQ_TX_WATERMARK) != 0u) ||
	       ((ctrl & ERISCV_UART_ERR_IRQ_ENABLE) != 0u &&
		(pending & ERISCV_UART_IRQ_RX_OVERRUN) != 0u);
}

static int eriscv_uart_irq_update(const struct device *dev)
{
	ARG_UNUSED(dev);
	return 1;
}

static void eriscv_uart_irq_callback_set(const struct device *dev,
					 uart_irq_callback_user_data_t callback,
					 void *user_data)
{
	struct eriscv_uart_data *data = dev->data;

	data->callback = callback;
	data->callback_data = user_data;
}

static void eriscv_uart_isr(const struct device *dev)
{
	struct eriscv_uart_data *data = dev->data;
	const struct eriscv_uart_config *config = dev->config;

	if (data->callback != NULL && eriscv_uart_irq_is_pending(dev)) {
		data->callback(dev, data->callback_data);
	} else if (data->callback == NULL) {
		eriscv_uart_ctrl_update(config, 0u, ERISCV_UART_RX_IRQ_ENABLE |
					       ERISCV_UART_TX_IRQ_ENABLE |
					       ERISCV_UART_ERR_IRQ_ENABLE);
	}
}
#endif

static int eriscv_uart_init(const struct device *dev)
{
	const struct eriscv_uart_config *config = dev->config;

	sys_write32(config->baud_divisor, config->base + ERISCV_UART_BAUDDIV);
	sys_write32(ERISCV_UART_TX_ENABLE | ERISCV_UART_RX_ENABLE,
		    config->base + ERISCV_UART_CTRL);
#ifdef CONFIG_UART_INTERRUPT_DRIVEN
	config->irq_config_func(dev);
#endif
	return 0;
}

static const struct uart_driver_api eriscv_uart_api = {
	.poll_in = eriscv_uart_poll_in,
	.poll_out = eriscv_uart_poll_out,
	.err_check = eriscv_uart_err_check,
#ifdef CONFIG_UART_INTERRUPT_DRIVEN
	.fifo_fill = eriscv_uart_fifo_fill,
	.fifo_read = eriscv_uart_fifo_read,
	.irq_tx_enable = eriscv_uart_irq_tx_enable,
	.irq_tx_disable = eriscv_uart_irq_tx_disable,
	.irq_tx_ready = eriscv_uart_irq_tx_ready,
	.irq_rx_enable = eriscv_uart_irq_rx_enable,
	.irq_rx_disable = eriscv_uart_irq_rx_disable,
	.irq_tx_complete = eriscv_uart_irq_tx_complete,
	.irq_rx_ready = eriscv_uart_irq_rx_ready,
	.irq_err_enable = eriscv_uart_irq_err_enable,
	.irq_err_disable = eriscv_uart_irq_err_disable,
	.irq_is_pending = eriscv_uart_irq_is_pending,
	.irq_update = eriscv_uart_irq_update,
	.irq_callback_set = eriscv_uart_irq_callback_set,
#endif
};

#ifdef CONFIG_UART_INTERRUPT_DRIVEN
#define ERISCV_UART_IRQ_CONFIG(inst) \
	static void eriscv_uart_irq_config_##inst(const struct device *dev) \
	{ \
		ARG_UNUSED(dev); \
		IRQ_CONNECT(DT_INST_IRQ(inst, irq), DT_INST_IRQ(inst, priority), \
			    eriscv_uart_isr, DEVICE_DT_INST_GET(inst), 0); \
		riscv_plic_set_priority(IRQ_TO_L2(DT_INST_IRQ(inst, irq)), \
					DT_INST_IRQ(inst, priority)); \
		irq_enable(IRQ_TO_L2(DT_INST_IRQ(inst, irq))); \
	}
#else
#define ERISCV_UART_IRQ_CONFIG(inst)
#endif

#define ERISCV_UART_INIT(inst) \
	ERISCV_UART_IRQ_CONFIG(inst) \
	static const struct eriscv_uart_config eriscv_uart_config_##inst = { \
		.base = DT_INST_REG_ADDR(inst), \
		.baud_divisor = CONFIG_UART_ERISCV_BAUD_DIVISOR, \
		IF_ENABLED(CONFIG_UART_INTERRUPT_DRIVEN, \
			(.irq_config_func = eriscv_uart_irq_config_##inst,)) \
	}; \
	static struct eriscv_uart_data eriscv_uart_data_##inst; \
	DEVICE_DT_INST_DEFINE(inst, eriscv_uart_init, NULL, &eriscv_uart_data_##inst, \
				&eriscv_uart_config_##inst, PRE_KERNEL_1, \
				CONFIG_SERIAL_INIT_PRIORITY, &eriscv_uart_api)

DT_INST_FOREACH_STATUS_OKAY(ERISCV_UART_INIT);
