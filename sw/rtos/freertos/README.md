# FreeRTOS M-mode development profile

This static-allocation M2 demo uses the upstream FreeRTOS-Kernel V11.3.0
RISC-V port. It creates four static application tasks: two equal-priority
yield/time-slice tasks, a timer trigger, and a higher-priority consumer. CLINT
`mtime` drives the scheduler tick; an initial empty-queue receive proves the
timeout path, then an APB timer routed through the PLIC sends both a queue item
and task notification from an ISR. Each task records completion and deletes
itself; the consumer prints `FreeRTOS M-mode PASS` and writes
`eriscv_freertos_result = 1` only after all four completion records exist.

The supported surface is static allocation by default; dynamic allocation
(`configSUPPORT_DYNAMIC_ALLOCATION=1`, `heap_4.c`, 8 KiB heap) is also
available and verified in ModelSim. `test_malloc()` runs `pvPortMalloc` /
`vPortFree` before the scheduler starts; the consumer task asserts
`eriscv_freertos_malloc_ok == 1`. All tasks remain in M-mode, and the five
task stacks (four application plus idle) reserve `5 × 128 × 4 = 2,560` bytes
of DTCM.

Build images with `make -C eriscv-m2/sw/rtos/freertos images`.
Run the ModelSim timing profile once with:

```sh
python3 eriscv-m2/sw/tools/run_freertos_sim.py
```

Run the qualification evidence with:

```sh
python3 eriscv-m2/sw/tools/run_freertos_sim.py --runs 3 --failstops
```

The runner extracts the ten-word `eriscv_freertos_timing_report` ABI and
combines it with a TB-observed APB-timer PLIC-source assertion. It reports
yield A→B/B→A, tick→first B instruction, source→C-level ISR, and
ISR→consumer-wake deltas. It rejects missing/zero boundaries and non-identical
metrics across repeated runs. The default runner executes only the normal
profile. `--failstops` additionally rebuilds two controlled negative images:
an application assertion and an untouched stack-guard-word corruption. Both
must reach the fail-stop result `0xdead0001`. Current measurement boundaries
are in the [family performance manual](https://eriscv-mcu-product-manual.zhanxnse.chatgpt.site/performance).

## Driver layout

FreeRTOS-specific BSP drivers live under `drivers/`, one pair per peripheral:
`uart.{c,h}`, `clk_rst.{c,h}`, `gpio.{c,h}`, `timer.{c,h}`, `plic.{c,h}`,
`wdt.{c,h}`, and `spi.{c,h}`. `drivers.h` only aggregates those public headers; the shared
`sw/include/eriscv_mcu.h` remains the low-level MMIO compatibility layer.

The SPI driver supports all four chip-selects, mode-0/1/2/3 and LSB-first
configuration, repeated 8-bit frames under one chip-select, polling transfers,
and PLIC-backed asynchronous transfers. The asynchronous completion callback
runs in interrupt context.
