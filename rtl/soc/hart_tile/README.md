# AP hart tile

`ap_hart_tile` is the only per-hart integration unit instantiated by the AP
cluster. All implementation below it lives here:

```text
rtl/soc/hart_tile/
  ap_hart_tile.sv              structural external boundary
  core/                         RV64GC execution pipeline and architectural IP
    riscv_core.sv
    mmu/                        Sv39 TLB/PTW/control primitives
  mem/                          hart-private integration
    ap_hart_memory_frontend.sv  Sv39, private L1 caches, and AXI managers
    cache/
    axi/
```

ITLB, DTLB, the shared Sv39 PTW, translation faults, and `SFENCE.VMA` are
per-hart state. MMIO passes through DTLB when translation is enabled, then
bypasses D-Cache after physical-address decode. The PTW uses its dedicated,
cacheable D-Cache port.

Shared AXI fabric, Boot ROM, DDR, peripherals, and debug transport remain
outside this directory at SoC scope.
