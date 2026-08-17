# AP Ethernet subsystem

This directory owns the Ethernet subsystem boundary, its DDR AXI manager,
MAC/DMA/control RTL, and PHY-facing integration. Ethernet is neither a
generic APB peripheral nor part of the memory system: it masters `axi_mem` for
payload traffic and raises an interrupt into `peripherals/`.

The MAC closure is the MIT-licensed `alexforencich/verilog-ethernet`
revision `77320a9471d19c7dd383914bc049e02d9f4f1ffb`, vendored as the minimal
`eth_mac_1g` GMII closure in `rtl/vendor/verilog_ethernet`. Its generic `lfsr`
module is renamed `ap_eth_lfsr` to avoid the AP common-cells module collision.
`make -C dv/soc/sim eth-mac-lint` checks this closure with duplicate-module and
missing-pin diagnostics fatal.

`fpga/vcu108/ip/gig_ethernet_pcs_pma/create_ip.tcl` is the source-controlled
VCU108 SGMII PCS/PMA configuration. The future board top owns PCS/PMA clocks,
SGMII pins, MDIO/MDC, PHY reset, and PHY interrupt; the portable subsystem
terminates at GMII.

The current RTL integrates an APB-controlled, direct physical-buffer DMA path: one
posted TX buffer and one posted RX buffer, 64-bit AXI4 DDR traffic, byte-stream
CDC, and the GMII MAC.  DMA addresses must be eight-byte aligned; TX length is at most 1536 bytes and
posted RX capacity is at most 2048 bytes. TX begins at GMII only after the full
DMA frame is in the asynchronous FIFO, so a faster PHY clock cannot underflow it.  It is deliberately not a Linux
descriptor-ring engine.

Software owns non-coherent cache transfer with `CBO.CLEAN` plus `FENCE` before TX
and `CBO.INVAL` plus `FENCE` after RX; hardware does not yet inject external
D-Cache or LR/SC-reservation invalidations.  Drivers must not execute LR/SC on a
buffer while it is device-owned.
