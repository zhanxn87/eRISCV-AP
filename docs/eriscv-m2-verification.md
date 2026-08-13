# eRISCV-M2 Verification Contract

This contract defines the verification method, required coverage, and evidence
boundaries for the M2 architecture claim. Dated totals, commands, and tool
evidence belong in the
[MCU Verification Evidence Snapshot](../../docs/Verification/eriscv-mcu-simulation-evidence-snapshot.md).
Routed timing and utilization belong in
[FPGA Timing and Area Evidence](../../docs/Performance/eriscv-mcu-fpga-timing-area-evidence.md).

## Evidence Method

- Verilator product-directed core/SoC regression is the default path. ModelSim
  is used for focused debug and waveform inspection.
- ACT4 runs in the core TB. Boot transport, image loading, and `crt0`
  initialization run in the SoC TB.
- Exact runnable tests, inputs, and runners are owned by the
  [design-verification inventory](../dv/README.md) and
  [ACT4 profile](../compliance/riscv-arch-test/README.md).
- M2 uses its own RTL, DV, software, compliance, and FPGA artifacts; evidence
  from another product does not close an M2 requirement.

## Required Coverage

| Area | Required coverage |
| --- | --- |
| RV32F and Zcf | Arithmetic, conversion, comparison, FMA, `FLW`/`FSW`, compressed FP loads/stores, rounding, FCSR/`fflags`, FS-Off illegality, NaN/subnormal/divide/square-root, and precise trap/debug ordering. |
| Pipeline and protection | Hazard, forwarding, stall, flush, branch, trap, interrupt, debug, M/U mode, `mcounteren`, and 16-entry PMP CSR/TOR/NA4/NAPOT/MPRV/fault coverage. |
| Memories and DMA | ITCM/DTCM boundaries; eight-bank System SRAM mapping, arbitration, and errors; direct/descriptor DMA, firewall, ABORT, source-5 PLIC/MEI/WFI, descriptor errors/loop/limit, CPU/DMA contention, and UART-TX byte-stream backpressure. |
| Toolchain and workloads | Exact `rv32imfc_zicsr_zifencei_zicntr_zihpm_zihintpause_zba_zbb_zbs_zicond_zcf` / `ilp32f` build contract, BSP, standard-B/Zicond generation, RV32F FFT, and representative software workloads |
| No-cache rule | Structural and regression evidence that no cache, cacheable alias, cache-maintenance operation, or coherency path is present. |

## Evidence Boundaries

- Generic DMA is limited to System-SRAM transfers plus the fixed UART0-TX byte
  stream. UART RX, SPI, Timer, Ethernet, and Wi-Fi are not generic-DMA
  endpoints.
- PMP constrains CPU accesses; it does not automatically constrain DMA.
- RV32F task-context save/restore is not an automatic hardware service and
  remains outside the current FreeRTOS profile contract.
- Passing simulation does not establish routed timing closure or physical-board
  behavior. Consult the evidence documents linked above for current status.
