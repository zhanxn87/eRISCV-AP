// SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
// SPDX-License-Identifier: GPL-2.0-only

#include <linux/bitops.h>
#include <linux/dma-mapping.h>
#include <linux/etherdevice.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/iopoll.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/netdevice.h>
#include <linux/platform_device.h>
#include <linux/spinlock.h>
#include <linux/slab.h>

#define AP_ETH_REG_CTRL            0x000
#define AP_ETH_REG_IRQ_STATUS      0x004
#define AP_ETH_REG_IRQ_ENABLE      0x008
#define AP_ETH_REG_STATUS          0x00c
#define AP_ETH_REG_TX_BASE_LO      0x010
#define AP_ETH_REG_TX_BASE_HI      0x014
#define AP_ETH_REG_TX_COUNT        0x018
#define AP_ETH_REG_TX_TAIL         0x01c
#define AP_ETH_REG_TX_HEAD         0x020
#define AP_ETH_REG_TX_DOORBELL     0x024
#define AP_ETH_REG_RX_BASE_LO      0x030
#define AP_ETH_REG_RX_BASE_HI      0x034
#define AP_ETH_REG_RX_COUNT        0x038
#define AP_ETH_REG_RX_TAIL         0x03c
#define AP_ETH_REG_RX_HEAD         0x040
#define AP_ETH_REG_RX_DOORBELL     0x044
#define AP_ETH_REG_CAPS            0x050
#define AP_ETH_REG_MAC_LO          0x054
#define AP_ETH_REG_MAC_HI          0x058

#define AP_ETH_CTRL_TX_ENABLE      BIT(0)
#define AP_ETH_CTRL_RX_ENABLE      BIT(1)
#define AP_ETH_CTRL_RING_RESET     BIT(2)
#define AP_ETH_IRQ_ALL             GENMASK(3, 0)

#define AP_ETH_DESC_OWN            BIT_ULL(16)
#define AP_ETH_DESC_IOC            BIT_ULL(17)
#define AP_ETH_DESC_EOP            BIT_ULL(18)
#define AP_ETH_DESC_DONE           BIT_ULL(0)
#define AP_ETH_DESC_ERROR          BIT_ULL(1)
#define AP_ETH_DESC_ACTUAL_SHIFT   16
#define AP_ETH_DESC_ACTUAL_MASK    GENMASK_ULL(31, 16)

#define AP_ETH_RING_SIZE            64
#define AP_ETH_RING_MASK            (AP_ETH_RING_SIZE - 1)
#define AP_ETH_TX_MAX_BYTES         1536
#define AP_ETH_RX_BUF_BYTES         2048

/*
 * Hardware transfers four 64-bit words per descriptor.  The low 48 address
 * bits and the descriptor alignment are checked by RTL before DMA starts.
 */
struct ap_eth_desc {
	__le64 buffer_addr;
	__le64 length_flags;
	__le64 status;
	__le64 cookie;
} __packed __aligned(32);

static_assert(sizeof(struct ap_eth_desc) == 32);

struct ap_eth_priv {
	struct device *dev;
	struct net_device *ndev;
	void __iomem *io_base;
	int irq;
	struct napi_struct napi;
	spinlock_t tx_lock;

	struct ap_eth_desc *tx_ring;
	dma_addr_t tx_ring_dma;
	struct ap_eth_desc *rx_ring;
	dma_addr_t rx_ring_dma;
	struct sk_buff *tx_skb[AP_ETH_RING_SIZE];
	void *tx_bounce_alloc[AP_ETH_RING_SIZE];
	void *tx_bounce[AP_ETH_RING_SIZE];
	dma_addr_t tx_dma[AP_ETH_RING_SIZE];
	struct sk_buff *rx_skb[AP_ETH_RING_SIZE];
	dma_addr_t rx_dma[AP_ETH_RING_SIZE];
	u16 tx_prod;
	u16 tx_clean;
	u16 rx_cons;
	u16 rx_prod;
};

static inline void ap_eth_writel(struct ap_eth_priv *priv, u32 reg, u32 value)
{
	writel(value, priv->io_base + reg);
}

static inline u32 ap_eth_readl(struct ap_eth_priv *priv, u32 reg)
{
	return readl(priv->io_base + reg);
}

static inline u16 ap_eth_ring_next(u16 index)
{
	return (index + 1) & AP_ETH_RING_MASK;
}

static inline bool ap_eth_dma_addr_valid(dma_addr_t addr, unsigned int align)
{
	return !(addr & ~DMA_BIT_MASK(48)) && IS_ALIGNED(addr, align);
}

static inline bool ap_eth_tx_ring_full(const struct ap_eth_priv *priv, u16 head)
{
	return ap_eth_ring_next(priv->tx_prod) == head;
}

static void ap_eth_desc_set(struct ap_eth_desc *desc, dma_addr_t dma, u16 length)
{
	WRITE_ONCE(desc->buffer_addr, cpu_to_le64(dma));
	WRITE_ONCE(desc->length_flags,
		   cpu_to_le64(length | AP_ETH_DESC_OWN | AP_ETH_DESC_IOC |
			       AP_ETH_DESC_EOP));
	WRITE_ONCE(desc->status, 0);
	WRITE_ONCE(desc->cookie, 0);
}

static struct sk_buff *ap_eth_alloc_rx_skb(struct net_device *ndev)
{
	struct sk_buff *skb;
	unsigned long aligned;

	/* RTL requires an 8-byte buffer address; do not apply NET_IP_ALIGN here. */
	skb = netdev_alloc_skb(ndev, AP_ETH_RX_BUF_BYTES + 7);
	if (!skb)
		return NULL;
	aligned = (unsigned long)PTR_ALIGN(skb->data, 8);
	skb_reserve(skb, aligned - (unsigned long)skb->data);
	return skb;
}

static int ap_eth_post_rx_buffer(struct ap_eth_priv *priv, u16 index,
				 struct sk_buff *skb)
{
	dma_addr_t dma;

	dma = dma_map_single(priv->dev, skb->data, AP_ETH_RX_BUF_BYTES,
				 DMA_FROM_DEVICE);
	if (dma_mapping_error(priv->dev, dma) || !ap_eth_dma_addr_valid(dma, 8)) {
		if (!dma_mapping_error(priv->dev, dma))
			dma_unmap_single(priv->dev, dma, AP_ETH_RX_BUF_BYTES,
					 DMA_FROM_DEVICE);
		return -EIO;
	}

	priv->rx_skb[index] = skb;
	priv->rx_dma[index] = dma;
	ap_eth_desc_set(&priv->rx_ring[index], dma, AP_ETH_RX_BUF_BYTES);
	return 0;
}

static void ap_eth_free_rings(struct ap_eth_priv *priv)
{
	unsigned int index;

	for (index = 0; index < AP_ETH_RING_SIZE; index++) {
		if (priv->tx_skb[index]) {
			dma_unmap_single(priv->dev, priv->tx_dma[index],
					 priv->tx_skb[index]->len, DMA_TO_DEVICE);
			dev_kfree_skb_any(priv->tx_skb[index]);
			priv->tx_skb[index] = NULL;
		}
		kfree(priv->tx_bounce_alloc[index]);
		priv->tx_bounce_alloc[index] = NULL;
		priv->tx_bounce[index] = NULL;
		if (priv->rx_skb[index]) {
			dma_unmap_single(priv->dev, priv->rx_dma[index],
					 AP_ETH_RX_BUF_BYTES, DMA_FROM_DEVICE);
			dev_kfree_skb_any(priv->rx_skb[index]);
			priv->rx_skb[index] = NULL;
		}
	}

	if (priv->tx_ring) {
		dma_free_coherent(priv->dev,
				  sizeof(*priv->tx_ring) * AP_ETH_RING_SIZE,
				  priv->tx_ring, priv->tx_ring_dma);
		priv->tx_ring = NULL;
	}
	if (priv->rx_ring) {
		dma_free_coherent(priv->dev,
				  sizeof(*priv->rx_ring) * AP_ETH_RING_SIZE,
				  priv->rx_ring, priv->rx_ring_dma);
		priv->rx_ring = NULL;
	}
}

static int ap_eth_alloc_rings(struct ap_eth_priv *priv)
{
	unsigned int index;
	int ret;

	priv->tx_ring = dma_alloc_coherent(priv->dev,
					   sizeof(*priv->tx_ring) * AP_ETH_RING_SIZE,
					   &priv->tx_ring_dma, GFP_KERNEL);
	priv->rx_ring = dma_alloc_coherent(priv->dev,
					   sizeof(*priv->rx_ring) * AP_ETH_RING_SIZE,
					   &priv->rx_ring_dma, GFP_KERNEL);
	if (!priv->tx_ring || !priv->rx_ring ||
	    !ap_eth_dma_addr_valid(priv->tx_ring_dma, 32) ||
	    !ap_eth_dma_addr_valid(priv->rx_ring_dma, 32)) {
		ret = -ENOMEM;
		goto err_free;
	}

	memset(priv->tx_ring, 0, sizeof(*priv->tx_ring) * AP_ETH_RING_SIZE);
	memset(priv->rx_ring, 0, sizeof(*priv->rx_ring) * AP_ETH_RING_SIZE);
	priv->tx_prod = 0;
	priv->tx_clean = 0;
	priv->rx_cons = 0;
	priv->rx_prod = AP_ETH_RING_SIZE - 1;

	/* Keep one slot empty: TAIL is the one-past-last hardware-owned slot. */
	for (index = 0; index < AP_ETH_RING_SIZE - 1; index++) {
		struct sk_buff *skb = ap_eth_alloc_rx_skb(priv->ndev);

		if (!skb) {
			ret = -ENOMEM;
			goto err_free;
		}
		ret = ap_eth_post_rx_buffer(priv, index, skb);
		if (ret) {
			dev_kfree_skb_any(skb);
			goto err_free;
		}
	}
	return 0;

err_free:
	ap_eth_free_rings(priv);
	return ret;
}

static int ap_eth_wait_idle(struct ap_eth_priv *priv)
{
	u32 status;

	return readl_poll_timeout(priv->io_base + AP_ETH_REG_STATUS, status,
				  !status, 10, 100000);
}

static int ap_eth_hw_stop(struct ap_eth_priv *priv)
{
	ap_eth_writel(priv, AP_ETH_REG_IRQ_ENABLE, 0);
	/* Stop new RX work first; active TX drains through the PHY staging path. */
	ap_eth_writel(priv, AP_ETH_REG_CTRL, AP_ETH_CTRL_TX_ENABLE);
	if (ap_eth_wait_idle(priv))
		return -ETIMEDOUT;
	ap_eth_writel(priv, AP_ETH_REG_CTRL, 0);
	return 0;
}

static void ap_eth_hw_program(struct ap_eth_priv *priv)
{
	u64 tx_base = priv->tx_ring_dma;
	u64 rx_base = priv->rx_ring_dma;

	/* Descriptors and RX buffers must become visible before their tails. */
	dma_wmb();
	ap_eth_writel(priv, AP_ETH_REG_TX_BASE_LO, lower_32_bits(tx_base));
	ap_eth_writel(priv, AP_ETH_REG_TX_BASE_HI, upper_32_bits(tx_base));
	ap_eth_writel(priv, AP_ETH_REG_TX_COUNT, AP_ETH_RING_SIZE);
	ap_eth_writel(priv, AP_ETH_REG_TX_TAIL, 0);
	ap_eth_writel(priv, AP_ETH_REG_RX_BASE_LO, lower_32_bits(rx_base));
	ap_eth_writel(priv, AP_ETH_REG_RX_BASE_HI, upper_32_bits(rx_base));
	ap_eth_writel(priv, AP_ETH_REG_RX_COUNT, AP_ETH_RING_SIZE);
	ap_eth_writel(priv, AP_ETH_REG_RX_TAIL, priv->rx_prod);
	ap_eth_writel(priv, AP_ETH_REG_IRQ_STATUS, AP_ETH_IRQ_ALL);
	ap_eth_writel(priv, AP_ETH_REG_CTRL,
		       AP_ETH_CTRL_TX_ENABLE | AP_ETH_CTRL_RX_ENABLE);
	ap_eth_writel(priv, AP_ETH_REG_IRQ_ENABLE, AP_ETH_IRQ_ALL);
	ap_eth_writel(priv, AP_ETH_REG_RX_DOORBELL, 1);
}

static void ap_eth_tx_reclaim(struct ap_eth_priv *priv)
{
	u16 head = ap_eth_readl(priv, AP_ETH_REG_TX_HEAD);

	while (priv->tx_clean != head) {
		u16 index = priv->tx_clean;
		struct ap_eth_desc *desc = &priv->tx_ring[index];
		u64 status = le64_to_cpu(READ_ONCE(desc->status));
		struct sk_buff *skb = priv->tx_skb[index];

		if (!(status & AP_ETH_DESC_DONE))
			break;
		if (status & AP_ETH_DESC_ERROR)
			priv->ndev->stats.tx_errors++;
		else
			priv->ndev->stats.tx_packets++;
		priv->ndev->stats.tx_bytes += skb->len;
		dma_unmap_single(priv->dev, priv->tx_dma[index], skb->len,
				 DMA_TO_DEVICE);
		dev_kfree_skb_any(skb);
		kfree(priv->tx_bounce_alloc[index]);
		priv->tx_skb[index] = NULL;
		priv->tx_bounce_alloc[index] = NULL;
		priv->tx_bounce[index] = NULL;
		WRITE_ONCE(desc->status, 0);
		priv->tx_clean = ap_eth_ring_next(index);
	}

	if (netif_queue_stopped(priv->ndev) &&
	    !ap_eth_tx_ring_full(priv, ap_eth_readl(priv, AP_ETH_REG_TX_HEAD)))
		netif_wake_queue(priv->ndev);
}

static int ap_eth_rx_poll(struct ap_eth_priv *priv, int budget)
{
	int work_done = 0;
	bool tail_advanced = false;

	while (work_done < budget) {
		u16 index = priv->rx_cons;
		struct ap_eth_desc *desc = &priv->rx_ring[index];
		u64 status = le64_to_cpu(READ_ONCE(desc->status));
		struct sk_buff *skb;
		struct sk_buff *replacement;
		u16 length;

		if (!(status & AP_ETH_DESC_DONE))
			break;

		skb = priv->rx_skb[index];
		priv->rx_skb[index] = NULL;
		dma_unmap_single(priv->dev, priv->rx_dma[index], AP_ETH_RX_BUF_BYTES,
				 DMA_FROM_DEVICE);
		length = (status & AP_ETH_DESC_ACTUAL_MASK) >> AP_ETH_DESC_ACTUAL_SHIFT;
		replacement = ap_eth_alloc_rx_skb(priv->ndev);

		if ((status & AP_ETH_DESC_ERROR) || length > AP_ETH_RX_BUF_BYTES) {
			priv->ndev->stats.rx_errors++;
			dev_kfree_skb_any(skb);
		} else if (replacement) {
			skb_put(skb, length);
			priv->ndev->stats.rx_packets++;
			priv->ndev->stats.rx_bytes += length;
			napi_gro_receive(&priv->napi, skb);
			skb = NULL;
		} else {
			/* Preserve ring ownership under memory pressure by dropping the frame. */
			priv->ndev->stats.rx_dropped++;
			skb_trim(skb, 0);
			replacement = skb;
			skb = NULL;
		}

		if (!replacement)
			replacement = ap_eth_alloc_rx_skb(priv->ndev);
		if (!replacement || ap_eth_post_rx_buffer(priv, priv->rx_prod,
						       replacement)) {
			priv->ndev->stats.rx_dropped++;
			dev_kfree_skb_any(replacement);
			/* Stop before a stale completion can be consumed again. */
			priv->rx_cons = ap_eth_ring_next(index);
			work_done++;
			ap_eth_writel(priv, AP_ETH_REG_CTRL, 0);
			break;
		}

		priv->rx_cons = ap_eth_ring_next(index);
		priv->rx_prod = ap_eth_ring_next(priv->rx_prod);
		tail_advanced = true;
		work_done++;
	}

	if (tail_advanced) {
		dma_wmb();
		ap_eth_writel(priv, AP_ETH_REG_RX_TAIL, priv->rx_prod);
		ap_eth_writel(priv, AP_ETH_REG_RX_DOORBELL, 1);
	}
	return work_done;
}

static int ap_eth_napi_poll(struct napi_struct *napi, int budget)
{
	struct ap_eth_priv *priv = container_of(napi, struct ap_eth_priv, napi);
	unsigned long flags;
	int work_done;

	spin_lock_irqsave(&priv->tx_lock, flags);
	ap_eth_tx_reclaim(priv);
	spin_unlock_irqrestore(&priv->tx_lock, flags);
	work_done = ap_eth_rx_poll(priv, budget);

	if (work_done < budget && napi_complete_done(napi, work_done)) {
		ap_eth_writel(priv, AP_ETH_REG_IRQ_ENABLE, AP_ETH_IRQ_ALL);
		if (ap_eth_readl(priv, AP_ETH_REG_IRQ_STATUS)) {
			ap_eth_writel(priv, AP_ETH_REG_IRQ_ENABLE, 0);
			napi_schedule(napi);
		}
	}
	return work_done;
}

static irqreturn_t ap_eth_irq(int irq, void *data)
{
	struct net_device *ndev = data;
	struct ap_eth_priv *priv = netdev_priv(ndev);
	u32 cause = ap_eth_readl(priv, AP_ETH_REG_IRQ_STATUS);

	(void)irq;

	if (!cause)
		return IRQ_NONE;
	ap_eth_writel(priv, AP_ETH_REG_IRQ_STATUS, cause);
	ap_eth_writel(priv, AP_ETH_REG_IRQ_ENABLE, 0);
	napi_schedule_irqoff(&priv->napi);
	return IRQ_HANDLED;
}

static netdev_tx_t ap_eth_start_xmit(struct sk_buff *skb, struct net_device *ndev)
{
	struct ap_eth_priv *priv = netdev_priv(ndev);
	unsigned long flags;
	u16 index;
	u16 head;
	void *allocation;
	void *bounce;
	dma_addr_t dma;

	if (unlikely(skb_is_nonlinear(skb) || skb->len > AP_ETH_TX_MAX_BYTES)) {
		ndev->stats.tx_dropped++;
		dev_kfree_skb_any(skb);
		return NETDEV_TX_OK;
	}

	allocation = kmalloc(skb->len + 7, GFP_ATOMIC);
	if (!allocation)
		return NETDEV_TX_BUSY;
	bounce = PTR_ALIGN(allocation, 8);
	memcpy(bounce, skb->data, skb->len);
	dma = dma_map_single(priv->dev, bounce, skb->len, DMA_TO_DEVICE);
	if (dma_mapping_error(priv->dev, dma) || !ap_eth_dma_addr_valid(dma, 8)) {
		if (!dma_mapping_error(priv->dev, dma))
			dma_unmap_single(priv->dev, dma, skb->len, DMA_TO_DEVICE);
		kfree(allocation);
		ndev->stats.tx_dropped++;
		dev_kfree_skb_any(skb);
		return NETDEV_TX_OK;
	}

	spin_lock_irqsave(&priv->tx_lock, flags);
	ap_eth_tx_reclaim(priv);
	head = ap_eth_readl(priv, AP_ETH_REG_TX_HEAD);
	if (ap_eth_tx_ring_full(priv, head)) {
		netif_stop_queue(ndev);
		spin_unlock_irqrestore(&priv->tx_lock, flags);
		dma_unmap_single(priv->dev, dma, skb->len, DMA_TO_DEVICE);
		kfree(allocation);
		return NETDEV_TX_BUSY;
	}

	index = priv->tx_prod;
	priv->tx_skb[index] = skb;
	priv->tx_bounce_alloc[index] = allocation;
	priv->tx_bounce[index] = bounce;
	priv->tx_dma[index] = dma;
	ap_eth_desc_set(&priv->tx_ring[index], dma, skb->len);
	priv->tx_prod = ap_eth_ring_next(index);
	dma_wmb();
	ap_eth_writel(priv, AP_ETH_REG_TX_TAIL, priv->tx_prod);
	ap_eth_writel(priv, AP_ETH_REG_TX_DOORBELL, 1);
	if (ap_eth_tx_ring_full(priv, ap_eth_readl(priv, AP_ETH_REG_TX_HEAD)))
		netif_stop_queue(ndev);
	spin_unlock_irqrestore(&priv->tx_lock, flags);
	return NETDEV_TX_OK;
}

static int ap_eth_open(struct net_device *ndev)
{
	struct ap_eth_priv *priv = netdev_priv(ndev);
	int ret;

	if (priv->tx_ring || priv->rx_ring)
		return -EBUSY;
	napi_enable(&priv->napi);
	ret = ap_eth_hw_stop(priv);
	if (ret)
		goto err_napi;
	ap_eth_writel(priv, AP_ETH_REG_CTRL, AP_ETH_CTRL_RING_RESET);
	ret = ap_eth_alloc_rings(priv);
	if (ret)
		goto err_napi;
	ap_eth_hw_program(priv);
	netif_carrier_on(ndev); /* PCS/PMA link state is not yet exposed by portable RTL. */
	netif_start_queue(ndev);
	return 0;

err_napi:
	napi_disable(&priv->napi);
	return ret;
}

static int ap_eth_stop(struct net_device *ndev)
{
	struct ap_eth_priv *priv = netdev_priv(ndev);
	int ret;

	netif_stop_queue(ndev);
	ret = ap_eth_hw_stop(priv);
	if (ret) {
		netdev_err(ndev, "DMA did not become idle; preserving DMA mappings for recovery\n");
		napi_disable(&priv->napi);
		netif_carrier_off(ndev);
		return 0;
	}
	napi_disable(&priv->napi);
	ap_eth_writel(priv, AP_ETH_REG_CTRL, AP_ETH_CTRL_RING_RESET);
	ap_eth_free_rings(priv);
	netif_carrier_off(ndev);
	return 0;
}

static const struct net_device_ops ap_eth_netdev_ops = {
	.ndo_open		= ap_eth_open,
	.ndo_stop		= ap_eth_stop,
	.ndo_start_xmit	= ap_eth_start_xmit,
};

static void ap_eth_read_mac_address(struct ap_eth_priv *priv, u8 *address)
{
	u32 low = ap_eth_readl(priv, AP_ETH_REG_MAC_LO);
	u32 high = ap_eth_readl(priv, AP_ETH_REG_MAC_HI);

	address[0] = high >> 8;
	address[1] = high;
	address[2] = low >> 24;
	address[3] = low >> 16;
	address[4] = low >> 8;
	address[5] = low;
}

static int ap_eth_probe(struct platform_device *pdev)
{
	struct net_device *ndev;
	struct ap_eth_priv *priv;
	int ret;
	u8 mac[ETH_ALEN];

	ndev = alloc_etherdev(sizeof(*priv));
	if (!ndev)
		return -ENOMEM;
	SET_NETDEV_DEV(ndev, &pdev->dev);
	priv = netdev_priv(ndev);
	priv->dev = &pdev->dev;
	priv->ndev = ndev;
	spin_lock_init(&priv->tx_lock);
	priv->io_base = devm_platform_ioremap_resource(pdev, 0);
	if (IS_ERR(priv->io_base)) {
		ret = PTR_ERR(priv->io_base);
		goto err_free_netdev;
	}
	priv->irq = platform_get_irq(pdev, 0);
	if (priv->irq < 0) {
		ret = priv->irq;
		goto err_free_netdev;
	}
	ret = dma_set_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(48));
	if (ret)
		goto err_free_netdev;

	ndev->netdev_ops = &ap_eth_netdev_ops;
	ndev->min_mtu = ETH_MIN_MTU;
	ndev->max_mtu = AP_ETH_TX_MAX_BYTES - ETH_HLEN;
	netif_napi_add_weight(ndev, &priv->napi, ap_eth_napi_poll, NAPI_POLL_WEIGHT);
	ap_eth_writel(priv, AP_ETH_REG_IRQ_ENABLE, 0);
	ap_eth_writel(priv, AP_ETH_REG_CTRL, AP_ETH_CTRL_RING_RESET);
	if (device_get_mac_address(&pdev->dev, mac, ETH_ALEN))
		ap_eth_read_mac_address(priv, mac);
	if (!is_valid_ether_addr(mac))
		eth_random_addr(mac);
	eth_hw_addr_set(ndev, mac);

	ret = request_irq(priv->irq, ap_eth_irq, 0, dev_name(&pdev->dev), ndev);
	if (ret)
		goto err_del_napi;
	ret = register_netdev(ndev);
	if (ret)
		goto err_free_irq;
	platform_set_drvdata(pdev, ndev);
	dev_info(&pdev->dev, "AP Ethernet descriptor-ring DMA registered\n");
	return 0;

err_free_irq:
	free_irq(priv->irq, ndev);
err_del_napi:
	netif_napi_del(&priv->napi);
err_free_netdev:
	free_netdev(ndev);
	return ret;
}

static int ap_eth_remove(struct platform_device *pdev)
{
	struct net_device *ndev = platform_get_drvdata(pdev);
	struct ap_eth_priv *priv = netdev_priv(ndev);

	unregister_netdev(ndev);
	free_irq(priv->irq, ndev);
	netif_napi_del(&priv->napi);
	free_netdev(ndev);
	return 0;
}

static const struct of_device_id ap_eth_of_match[] = {
	{ .compatible = "eriscv,ap-ethernet-1.0" },
	{ }
};
MODULE_DEVICE_TABLE(of, ap_eth_of_match);

static struct platform_driver ap_eth_driver = {
	.probe = ap_eth_probe,
	.remove = ap_eth_remove,
	.driver = {
		.name = "eriscv-ap-ethernet",
		.of_match_table = ap_eth_of_match,
	},
};
module_platform_driver(ap_eth_driver);

MODULE_AUTHOR("Xianning Zhan");
MODULE_DESCRIPTION("eRISCV-AP descriptor-ring Ethernet driver");
MODULE_LICENSE("GPL");
