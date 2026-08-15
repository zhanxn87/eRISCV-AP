# eRISCV-AP verification

This directory contains the AP RTL verification entry points.  The portable AP
manifest is resolved from `rtl/riscv_core/filelist.f` and `rtl/soc/filelist.f`;
all focused tests use Verilator and write build products below `/tmp`.

## Core

```bash
make -C dv/core/sim check-filelist
make -C dv/core/sim rv64-directed
make -C dv/core/sim smode-csr
make -C dv/core/sim sfence-vma-meta
make -C dv/core/sim sv39-pte sv39-ptw sv39-tlb sv39-mmu-ctrl
make -C dv/core/sim cache-axi icache dcache
```

`rv64-directed` runs RV64I/M, load/store, compressed, F/D, A, FENCE, S-mode,
and SFENCE.VMA instruction programs.  The Sv39 targets separately cover PTE
permission checks, page-table walking, TLB behavior, and controller protocol.

## SoC

```bash
make -C dv/soc/sim check-filelist
make -C dv/soc/sim ap-soc-route
make -C dv/soc/sim ap-soc-periph-route
make -C dv/soc/sim ap-peripheral-subsystem
make -C dv/soc/sim ap-soc-sv39-route
make -C dv/soc/sim ap-soc-sv39-fault
make -C dv/soc/sim ap-soc-debug
```

The SoC tests cover Boot ROM -> I-Cache -> cacheable DDR routing, the
translated uncached peripheral path, local CLINT/PLIC/APB/BPI behavior, Sv39
translation and precise fault propagation, and debug halt/resume routing.
They use behavioral memory models; they do not validate a physical DDR4 MIG,
FPGA timing, boot firmware, or Linux boot.

## ModelSim hierarchy

With a Windows-accessible `vsim` bridge configured in WSL:

```bash
make -C dv/soc/sim modelsim-gui
```

This compiles the resolved AP SoC manifest and opens `ap_soc_elab_tb`.  It is a
hierarchy/debug workflow, not an FPGA or DDR4 calibration test.
