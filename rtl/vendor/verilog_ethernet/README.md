# verilog-ethernet vendor subset

This is the minimal source closure for `eth_mac_1g` from
[`alexforencich/verilog-ethernet`](https://github.com/alexforencich/verilog-ethernet),
revision `77320a9471d19c7dd383914bc049e02d9f4f1ffb`.

The upstream MIT license is retained in `COPYING`.  AP renames only the generic
`lfsr` module and its two MAC-internal references to `ap_eth_lfsr`, preventing a
collision with `rtl/vendor/common_cells`. Apart from that functional rename,
only trailing-whitespace normalization has been applied.

AP-specific AXI DMA, APB registers, and board PCS/PMA integration do not belong
in this directory.
