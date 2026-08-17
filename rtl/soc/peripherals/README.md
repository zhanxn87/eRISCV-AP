# AP peripheral subsystem

This directory owns the complete uncached-device tree: the peripheral AXI
crossbar (`axi/`), AXI-to-APB adapter and APB decoder (`apb/`), CLINT/PLIC,
and instantiated UART, SPI, timer, and GPIO IP.  `flash/ap_axi_bpi_nor.sv` is the
read-only AXI4-to-asynchronous-x16 BPI NOR target: it assembles aligned 64-bit
reads for first-stage boot and exposes BPI pins at the SoC boundary.  Program,
erase, and CFI command support are explicitly outside this first revision.

`clk_rst` and watchdog IP remain in `rtl/peripherals/`: neither is currently
instantiated by `ap_peripheral_subsystem`.
