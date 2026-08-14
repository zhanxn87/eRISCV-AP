# AP AXI integration RTL

This directory owns AP-specific AXI wrappers. It must not copy the frozen
PULP AXI implementation, which remains in `../../vendor/axi/`.

The implemented topology has two independent AXI planes:

- `axi_mem`: `ap_axi64_fabric.sv` arbitrates I-Cache, D-Cache, and the reserved
  Ethernet-DMA manager. It exposes DDR/MIG only. A local
  `ap_axi64_error_slave.sv` returns DECERR for an invalid non-DDR request.
- `axi_periph`: `ap_uncached_axi_master.sv` feeds
  `ap_peripheral_subsystem`. It is a 64-bit, one-beat, uncached AXI path that
  will terminate at the AXI-to-APB/device hierarchy.

`cache_axi4_line_adapter.sv` maps a blocking 64-byte cache-line operation to an
eight-beat 64-bit AXI4 burst. `cache_axi4_axi_bus_master.sv` and
`ap_axi64_egress_bridge.sv` only adapt project-owned flattened links to PULP
`AXI_BUS` interfaces.

No shared cache/MMIO mux remains in the AP SoC. Future L2/coherence wrappers
belong under `ap_memory_system`; AXI-to-APB and device adapters belong under
`ap_peripheral_subsystem`.
