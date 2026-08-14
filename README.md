# eRISCV-AP

eRISCV-AP is an RV64GC application-processor project targeting VCU108 DDR4.
The implemented AP boundary has one scalar in-order hart tile, private 32 KiB
I/D caches, a DDR-facing cacheable-memory subsystem, and an independent
uncached peripheral subsystem.

## Current implementation

`ap_soc` is now composed as:

```text
ap_cluster / ap_hart_tile
  ├── Boot ROM + RV64GC core
  ├── 32 KiB I-Cache -> axi_mem
  ├── 32 KiB D-Cache -> axi_mem
  └── uncached device master -> axi_periph
ap_memory_system       (I$, D$, reserved Ethernet DMA -> DDR)
ap_peripheral_subsystem (uncached AXI pass-through; decode is pending)
ap_ethernet_subsystem   (DMA/IRQ boundary reserved; MAC/DMA is pending)
```

`axi_mem` and `axi_periph` are independent at the hart-tile boundary; no shared
cache/MMIO ingress mux remains. `ap_memory_system` exports DDR only and returns
DECERR for accidental non-DDR traffic. The SoC smoke suite drives both paths
from real Boot ROM instructions:

- Boot ROM -> I-Cache -> `axi_mem` -> DDR, using an 8-beat 64-bit line fill.
- Boot ROM -> uncached `axi_periph`, while rejecting a DDR cache request.

The current RV64GC core and physical L1-cache milestone are not a Linux-capable
platform. S-mode, delegation, `satp`, Sv39, CLINT/PLIC/APB decode, DDR/MIG,
boot firmware, Ethernet DMA, and multi-hart coherence remain to be implemented.

## Start Here

- [RV64GC system architecture specification](docs/eriscv-ap-rv64gc-system-spec.md)
- [RV64GC core migration contract](docs/rv64gc-core-migration.md)
- [AP architecture diagram](docs/eRISCV-AP%20V3-64B.png)
- [Core verification](dv/core/README.md)
- [VCU108 integration](fpga/vcu108/README.md)
