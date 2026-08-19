# VCU108 BPI AXI EMC source IP

`axi_emc_bpi.xci` is the source-controlled Vivado 2025.2 configuration of
`xilinx.com:ip:axi_emc:3.0` for the VCU108 U58
`MT28GU01GAAA1EGC-0SIT` linear x16 NOR.

It exposes a 64-bit, 4-bit-ID AXI4 slave and a 32-bit *local* BPI aperture
covering `0x0000_0000..0x07ff_ffff` (128 MiB).  `rtl/ap_axi_bpi_bridge.sv` translates the SoC's 48-bit `AP_BPI_BASE` mapping to that aperture.

`C_USE_STARTUP=1` and `C_USE_STARTUP_INT=0` deliberately select an external
`STARTUPE3` wrapper.  BPI data[3:0], CE#, and CCLK are dedicated configuration
pins on VCU108 and cannot be assigned as ordinary top-level ports or XDC pins.
The VCU108 top implements the complete XAPP1282 mapping, including IOBUFs for
data[15:4], the 26-bit address truncation, `WAIT`, and timing constraints.

Run `../../scripts/create_axi_emc_bpi.tcl` with Vivado only when the XCI is
absent.  Generated targets, HDL, constraints, and example-design files are
build products and are intentionally not version controlled.
