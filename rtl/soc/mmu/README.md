# MMU ownership

ITLB, DTLB, shared Sv39 PTW, translation faults, and `SFENCE.VMA` control are
per-hart architectural state. Their final RTL home is:

```text
rtl/riscv_core/mmu/
  itlb.sv
  dtlb.sv
  sv39_ptw.sv
  sv39_pkg.sv
  mmu_ctrl.sv
```

They sit between the IF/LSU virtual-address producers and the physical I/D
cache interfaces. MMIO must pass through DTLB when translation is enabled, but
must bypass D-Cache after physical-address decode. The PTW uses physical,
cacheable page-table accesses through a dedicated D-Cache port.

This `rtl/soc/mmu/` directory is transitional documentation only. It must not
become the implementation home for hart-local translation state.
