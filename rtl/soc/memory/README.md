# AP shared memory system

This directory owns the shared cacheable-memory hierarchy, from `axi_mem`
arbitration to the DDR/MIG boundary. It must not copy the frozen PULP AXI
implementation, which remains in `../../vendor/axi/`.

`ap_axi_mem_xbar.sv` arbitrates I-Cache, D-Cache, and the reserved Ethernet DMA
manager. It exposes DDR only; `ap_axi64_error_slave.sv` terminates a non-DDR
address with DECERR. Future L2, coherence, DDR AXI adaptation, and MIG RTL
belong here.

Private Cache, TLB, and PTW logic belongs in `../hart_tile/mem/`; uncached
APB/BPI devices belong in `../peripherals/`; the Ethernet DMA manager belongs
in `../ethernet/`.
