# eRISCV-AP Linux Ethernet driver

`eriscv_ap_eth.c` is an out-of-tree platform `net_device` driver for the AP
Ethernet descriptor-ring ABI. It uses 64 descriptors per direction (63 usable;
one slot is kept empty to represent `HEAD == TAIL`), NAPI, PLIC interrupt 5,
and the Linux DMA API for the non-coherent DMA contract.

Build against a configured Linux tree:

```bash
make -C /path/to/linux M=$PWD modules
```

The device-tree node must use `compatible = "eriscv,ap-ethernet-1.0"`, map the
APB aperture at `0x10005000`, and supply PLIC source 5. `local-mac-address`
overrides the read-only MAC reset value. Do **not** add
`dma-coherent`: this RTL has a non-coherent DMA port. The Linux DMA API provides
the cache clean/invalidate and ordering needed by the architecture.

The portable MAC lacks MDIO and PCS/PMA link status, so the driver currently
uses a fixed carrier. It supports linear packets only, no checksum/TSO/RSS/VLAN
hardware offload, and no scatter-gather descriptors. TX uses an aligned bounce
buffer because the RTL requires every DMA buffer address to be 8-byte aligned.
