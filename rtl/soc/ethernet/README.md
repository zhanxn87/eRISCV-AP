# AP Ethernet subsystem

This directory owns the portable Ethernet subsystem: its APB control plane,
DDR AXI managers, clock-domain crossings, GMII MAC, and PLIC source 5. It is
an `axi_mem` manager, not part of the APB-only peripheral datapath.

The MAC closure is the MIT-licensed `alexforencich/verilog-ethernet` revision
`77320a9471d19c7dd383914bc049e02d9f4f1ffb`, vendored as the minimal
`eth_mac_1g` GMII closure in `rtl/vendor/verilog_ethernet`. Its generic `lfsr`
module is renamed `ap_eth_lfsr` to avoid the AP common-cells collision.
`make -C dv/soc/sim eth-mac-lint` checks the closure with duplicate-module and
missing-pin diagnostics fatal.

## DMA descriptor ABI

TX and RX use independent power-of-two DDR rings of 2..256 32-byte descriptors.
`HEAD == TAIL` is empty, so software keeps one descriptor unused. Ring bases
must be 32-byte aligned; DMA buffer addresses must be 8-byte aligned and use at
most physical address bit 47. `TAIL` is the one-past-last descriptor owned by
hardware. Publish descriptors, execute the DMA write barrier, write `TAIL`, then
write the matching doorbell.

Each descriptor is four little-endian 64-bit words:

| Offset | Producer | Contents |
| --- | --- | --- |
| `0x00` | software | buffer physical address `[47:0]` |
| `0x08` | software | length/capacity `[15:0]`, `OWN=16`, `IOC=17`, `EOP=18` |
| `0x10` | hardware | `DONE=0`, `ERROR=1`, error code `[15:8]`, actual length `[31:16]` |
| `0x18` | software | cookie/reserved |

TX is limited to 1536 bytes; RX capacity is limited to 2048 bytes. The ring
engine fetches descriptors and writes completion words through one AXI manager;
the payload DMA is a second AXI manager. `axi_mux_intf` combines them at the
single SoC-facing `axi_mem` boundary. TX completion follows full PHY staging and
MAC acceptance of the last byte; RX completion follows payload-DMA completion.

APB register offsets from `0x1000_5000`:

- `0x000 CTRL`: `TX_EN=0`, `RX_EN=1`, write-one `RING_RESET=2`.
- `0x004 IRQ_STATUS`: W1C `TX_DONE=0`, `TX_ERR=1`, `RX_DONE=2`, `RX_ERR=3`.
- `0x008 IRQ_ENABLE`; `0x00c STATUS` (`TX_BUSY=0`, `RX_BUSY=1`).
- TX: `0x010/014 BASE`, `0x018 COUNT`, `0x01c TAIL`, `0x020 HEAD`, `0x024 DOORBELL`.
- RX: `0x030/034 BASE`, `0x038 COUNT`, `0x03c TAIL`, `0x040 HEAD`, `0x044 DOORBELL`.
- `0x050 CAPS`, `0x054/058` read-only local MAC address.

Use `RING_RESET` only after `STATUS` is zero. The Linux driver disables new RX
work, drains TX, disables both directions, then resets both `HEAD` values before
programming new rings.

## Software and board boundary

`sw/linux/eriscv_ap_eth/` supplies the out-of-tree platform `net_device` driver.
It uses NAPI, PLIC interrupt 5, the Linux DMA API, a 64-entry ring (63 usable),
and an aligned TX bounce buffer. No `dma-coherent` DT property is valid: the
portable RTL is non-coherent. Bare-metal code must clean before TX and invalidate
after RX; Linux code must use the DMA API rather than hand-coded CBO sequences.

The portable subsystem terminates at GMII. The future VCU108 top owns the SGMII
PCS/PMA, MDIO/MDC, PHY reset/interrupt, and board clocks. Until that integration,
the driver uses a fixed carrier; no MDIO, link state, scatter-gather, checksum,
TSO, RSS, or VLAN hardware offload is claimed.
