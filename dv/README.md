# eRISCV-AP verification

This directory contains the AP RTL verification entry points.  The portable AP
manifest is resolved from `rtl/soc/hart_tile/filelist.f` and `rtl/soc/filelist.f`;
all focused tests use Verilator and write build products below `/tmp`.

## Hart tile

```bash
make -C dv/hart_tile/sim check-filelist
make -C dv/hart_tile/sim tile-smoke
make -C dv/hart_tile/sim rv64-directed
make -C dv/hart_tile/sim smode-csr
make -C dv/hart_tile/sim sfence-vma-meta
make -C dv/hart_tile/sim sv39-pte sv39-ptw sv39-tlb sv39-mmu-ctrl
make -C dv/hart_tile/sim cache-axi icache dcache
make -C dv/hart_tile/sim axi-mem-model
```

`tile-smoke` directly instantiates `ap_hart_tile` with its Boot ROM, both DDR AXI managers, and an idle MMIO manager. `rv64-directed` retains execution-pipeline instruction coverage.

`rv64-directed` runs RV64I/M, load/store, compressed, F/D, A, FENCE, S-mode,
and SFENCE.VMA instruction programs.  The Sv39 targets separately cover PTE
permission checks, page-table walking, TLB behavior, and controller protocol.
`axi-mem-model` covers the sparse full-physical-address AXI model: queued
transactions, address backpressure, response latency, byte strobes, and
SLVERR injection.  It is a protocol-level DDR surrogate, not a MIG/DDR4 PHY
model.

## SoC

```bash
make -C dv/soc/sim check-filelist
make -C dv/soc/sim ap-soc-route
make -C dv/soc/sim ap-soc-flash-boot-regression
make -C dv/soc/sim ap-soc-flash-boot-sv39
make -C dv/soc/sim ap-soc-periph-route
make -C dv/soc/sim ap-peripheral-subsystem
make -C dv/soc/sim ap-soc-sv39-route
make -C dv/soc/sim ap-soc-sv39-fault
make -C dv/soc/sim ap-soc-debug
```

The SoC tests cover Boot ROM -> I-Cache -> cacheable DDR routing, a complete
Boot ROM -> BPI -> DDR chain with checksum, FENCE.I, delayed-ready, corrupt
image, and cache-line-copy coverage, plus a boot-to-S-mode Sv39 path with
ITLB/DTLB/PTW A/D updates. They also cover the translated uncached peripheral
path, local CLINT/PLIC/APB/BPI behavior, precise Sv39 fault propagation, and
debug halt/resume routing.
The Sv39 route/fault regressions use the sparse full-physical-address model
with AXI latency and backpressure.  These behavioral models do not validate a
physical DDR4 MIG, FPGA timing, boot firmware, or Linux boot.

## ModelSim hierarchy

With a Windows-accessible `vsim` bridge configured in WSL:

```bash
make -C dv/soc/sim modelsim-gui
```

This compiles the resolved AP SoC manifest and opens `ap_soc_elab_tb`.  It is a
hierarchy/debug workflow, not an FPGA or DDR4 calibration test.
