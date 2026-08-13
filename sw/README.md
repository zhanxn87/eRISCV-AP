# eRISCV-M2 BSP & Example Suite

Freestanding bare-metal BSP for eRISCV-M2 (`rv32imfc_zicsr_zifencei_zicntr_zihpm_zihintpause_zba_zbb_zbs_zicond_zcf`,
`ilp32f`). No libc, startup library, or vendor SDK required. The examples
define the supported simulation suite; dated results are in the
[MCU Evidence Snapshot](../../docs/Verification/eriscv-mcu-simulation-evidence-snapshot.md).

## Software Inventory

| Layer | Files | M2 Notes |
|---|---|---|
| Startup | `lib/crt0.S` | Same as M0 |
| Linker | `linker/eriscv_mcu.ld` | Published ITCM/DTCM bounds and boot-entry symbols |
| Trap | `lib/trap.S` + `lib/trap.c` | M-mode trap entry; dispatches MEI/MTI/MSI |
| UART | `lib/uart.c` | Polling and asynchronous drivers use the published UART0 base |
| BSP header | `include/eriscv_mcu.h` | Same API; `ERISCV_MCU_HAS_M_EXT=1` enables hardware M |
| Config | `include/eriscv_mcu_config.h` | M2 address map, `ERISCV_MCU_BOOT_ADDR`, M/F/PMP configuration |
| DMA | `lib/dma.c` | One polling/IRQ-capable direct or linked-descriptor System SRAM channel, plus a direct System SRAM-to-UART0 TX endpoint |
| RTOS M-mode profile | `rtos/freertos/` | Four static M-mode tasks, timeout, queue/notification ISR handoff, and fail-stop checks |
| RTOS U-mode smoke | `rtos/freertos_umode/` | Four static U tasks, task-indexed PMP templates, and M-mode ECALL dispatch |
| Dhrystone | `benchmarks/dhrystone/` | Self-contained Dhrystone 2.1, mcycle timing, DMIPS/MHz reporting |
| Zephyr | `rtos/zephyr/` | Zephyr RTOS board port, multi-thread semaphore handoff demo |
| Tools | `tools/elf_to_mem.py`, `tools/run_hello_uart_sim.py`, `tools/run_mcu_ci.py` | Image generation and M2 BSP ModelSim checks |

## Driver API Summary

Same as M1 plus M2-specific:
- Hardware multiply/divide (M extension) — division uses native `div`/`rem`, no libgcc
- RV32F state/FCSR helpers; applications enable `mstatus.FS` explicitly before
  the first FP instruction
- PMP CSR helpers available (16-entry); the FreeRTOS U-mode smoke exercises
  task-indexed PMP templates, while the BSP examples remain M-mode
- Generic DMA direct/descriptor start, wait, status-clear, and source-5 IRQ
  helpers for aligned System SRAM copies and the fixed UART0 TX endpoint

## Examples

Build any example: `make -C eriscv-m2/sw EXAMPLE=<name> images`

| # | Example | Description | IRQs |
|---|---|---|---|
| 1 | `hello_uart` | Polling UART "hello" + GPIO pass flag | none |
| 2 | `timer_apb_poll` | APB Timer0 three-stage countdown | none |
| 3 | `timer_clint` | CLINT MTIMECMP periodic interrupt + GPIO blink | MTI |
| 4 | `wfi_tickless` | WFI idle + timer wake + wake counter | MTI |
| 5 | `irq_timer_uart` | Multi-source: timer blink + UART RX echo | MTI + MEI |
| 6 | `wdt_smoke` | Feed watchdog three times, then verify reset path | WDT |
| 7 | `dma_system_sram` | Generic DMA System SRAM copy driver smoke | polling DMA |
| 8 | `dma_irq_wfi` | DMA source-5 PLIC interrupt wakes WFI | MEI / DMA |
| 9 | `dma_descriptor_chain` | Generic DMA linked-descriptor copy smoke | descriptor fetch / SG |
| 10 | `dma_descriptor_irq_wfi` | Descriptor event on source-5 wakes WFI | MEI / descriptor DMA |
| 11 | `fpu_dma_sram` | DMA copied System SRAM binary32 data, RV32F arithmetic/FCSR, and Zcf load/store | polling DMA |
| 12 | `dma_uart_tx` | Direct System SRAM-to-UART0 TX byte stream with FIFO backpressure | polling DMA |
| 13 | `fpu_fft` | 128-point float radix-2 FFT versus Python binary32 reference | RV32F / FCSR |
| 14 | `fpu_fft1024` | 1024-point float radix-2 FFT extended stress versus Python binary32 reference | RV32F / FCSR |

`fpu_fft` is a CI example. `fpu_fft1024` is a manual extended stress test, so it does not lengthen the default CI suite. `async_uart` remains experimental and is not part of the CI suite.

`make fpu-fft-vectors` regenerates the checked-in vectors. The Python model forces
binary32 rounding after each add, subtract, and multiply; the firmware is built
with `-ffp-contract=off` and compares every real/imaginary output bit exactly.

The runner defaults to Verilator. Use `--backend modelsim` with the configured
ModelSim wrapper for focused single-case debugging or waveform inspection.
It derives `boot_addr` from the linked ELF entry point, so no separate BSP
simulation address setting exists.

## Build

```bash
make -C eriscv-m2/sw                    # hello_uart (default)
make -C eriscv-m2/sw EXAMPLE=timer_clint images
make -C eriscv-m2/sw fpu-fft-vectors    # regenerate binary32 reference vectors
make -C eriscv-m2/sw sim-fpu-fft         # 128-point RV32F FFT CI smoke
make -C eriscv-m2/sw sim-fpu-fft1024     # 1024-point RV32F FFT extended stress
make -C eriscv-m2/sw sim-fpu-fft1024-mcycle # FFT kernel mcycle measurement
make -C eriscv-m2/sw sim-fpu-dma-sram
make -C eriscv-m2/sw images-all          # CI example-set build
make -C eriscv-m2/sw ci                  # M2 BSP ModelSim CI
make -C eriscv-m2/sw sim                # run hello_uart sim
make -C eriscv-m2/sw sim-coremark       # CoreMark v1.01 smoke (Verilator preferred)
make -C eriscv-m2/sw sim-embench        # Embench-IoT matmult-int ModelSim smoke
make -C eriscv-m2/sw sim-dhrystone      # Dhrystone 2.1 smoke (Verilator preferred)
make -C eriscv-m2/sw sim-zephyr         # Zephyr RTOS multi-thread demo
make -C eriscv-m2/sw sim-freertos       # FreeRTOS M-mode timing profile
make -C eriscv-m2/sw sim-freertos-umode # FreeRTOS U-mode/PMP smoke
```

`isa.mk` is the product build contract. Bare-metal images default to the
fast simulation UART divisor (`UART_MODE=sim`); build a 100 MHz / 115200-baud
board image with `UART_MODE=board`. `UART_DIVISOR=<n>` remains available for
focused experiments. M2 bare-metal uses the full F/Zcf ISA and
`ilp32f`; FreeRTOS and Zephyr deliberately use `RTOS_ISA` plus `ilp32` until
their task-context save/restore includes F registers.

## CoreMark Simulation Smoke

The M2 CoreMark adapter uses the pinned upstream v1.01 submodule, one context,
2,000-byte static DTCM data, fixed validation seeds, and `mcycle` timing. The
default smoke runs one iteration through its automatic backend (Verilator when
available, otherwise ModelSim) and reports its cycle count.
It validates the CoreMark CRC path but is intentionally shorter than the
upstream 10-second reporting rule; it is not an official CoreMark or
CoreMark/MHz result.

## Dhrystone Simulation Smoke

The M2 Dhrystone adapter is a self-contained Dhrystone 2.1 implementation with
`mcycle` timing and UART output. The default smoke runs 1,000 iterations through
its automatic backend (Verilator when available, otherwise ModelSim) and reports
cycle count and DMIPS/MHz. It validates the
Dhrystone result word but is not an official Dhrystone or DMIPS rating.

Every successful runner invocation appends one row to
[`benchmarks/dhrystone/dmips_runs.csv`](benchmarks/dhrystone/dmips_runs.csv),
including ISA, Git state, code/image size, cycle count, DMIPS/MHz, and optional
HPM values. M2 does not yet expose the M0/M1 TB profile, so its dynamic
cross-word, IMEM-response, and detailed pipeline-diagnostic columns are
explicitly empty rather than inferred.

## Scope & Limitations

- M2 adds RV32F/Zcf, DMA, and System SRAM over the M1 baseline.
- PMP is exercised by the controlled FreeRTOS U-mode smoke; the BSP
  examples remain M-mode.
- U-mode is available for product software; supervisor mode is not implemented.
- The FreeRTOS U-mode smoke validates four static task contexts plus `yield` and
  `exit` ECALLs. It is not a production RTOS port.
- Board boot, flash/XIP, and production image format are not defined.
- The FreeRTOS profiles retain the integer ABI until they save/restore FP
  register state and FCSR per task.
- [toolchain.md](docs/toolchain.md) is the normative build and image contract.
