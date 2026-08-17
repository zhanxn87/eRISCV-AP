# verilog-axi subset

MIT-licensed AXI DMA source closure imported from
https://github.com/alexforencich/verilog-axi at
`516bd5dadc3365b7f9e225d2af8fe0b8d804fe53`.

Only `axi_dma`, `axi_dma_rd`, and `axi_dma_wr` are used by the AP Ethernet
subsystem.  The project-owned wrapper supplies the AP AXI interface, APB
control plane, PHY clock-domain crossings, and descriptor policy.
