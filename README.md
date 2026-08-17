# eRISCV-AP

eRISCV-AP is a single-hart RV64GC application-processor project.  Its portable
SoC RTL targets a VCU108 DDR4 C1 integration boundary.

## Current implementation

```text
ap_soc
├── ap_cluster
│   ├── shared Boot ROM
│   └── ap_hart_tile
│       ├── core/riscv_core (RV64GC, M/S/U)
│       └── ap_hart_memory_frontend
│           ├── Sv39 ITLB, DTLB, shared PTW, and precise faults
│           ├── private 32 KiB I-Cache and 32 KiB D-Cache
│           ├── cached DDR AXI managers
│           └── uncached translated MMIO AXI manager
├── ap_memory_system       (DDR-only cacheable fabric plus DECERR)
├── ap_peripheral_subsystem (CLINT, PLIC, APB peripherals, BPI egress)
└── ap_ethernet_subsystem  (DMA/IRQ boundary reserved)
```

`ap_hart_tile` is the canonical integration unit: its `core/riscv_core`
execution submodule connects to the hart-local memory frontend and exports
independent `axi_mem` and `axi_periph` managers.  Sv39
translation precedes physical cacheability decode, so MMIO bypasses D-Cache
but does not bypass DTLB.  Boot ROM fetches bypass I-Cache; DDR fetches use an
8-beat, 64-bit cache-line refill.

The VCU108 C1 MIG source IP is checked in for a 2 GiB DDR4 device with a
512-bit user AXI port.  The AP RTL still needs its board wrapper, address rebase,
64-to-512 AXI adaptation, reset/calibration handling, OpenSBI/DTB boot flow,
BPI controller, Ethernet DMA, and any multi-hart coherence path.  This is not
yet a Linux-boot completion claim.

Focused simulation evidence currently covers core RV64GC/S-mode/Sv39 directed
tests, a direct `ap_hart_tile` Boot ROM -> I-Cache -> DDR AXI smoke, a
sparse full-physical-address AXI DDR model, full Boot ROM -> BPI -> DDR
regressions (including S-mode Sv39), direct Sv39 routing and faults, and local
peripheral routing.  It does
not validate a physical DDR4 controller, FPGA timing, firmware, or Linux boot.

## Start here

- [RV64GC system architecture specification](docs/eriscv-ap-rv64gc-system-spec.md)
- [RV64GC core migration contract](docs/rv64gc-core-migration.md)
- [Verification](dv/README.md)
- [VCU108 integration](fpga/vcu108/README.md)
