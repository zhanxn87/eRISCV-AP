# M2 CoreMark Adapter

This adapter builds unmodified upstream CoreMark v1.01 sources against the M2
bare-metal BSP. It uses a single context, 2,000-byte static DTCM data, and a
fixed validation seed (`0x3415`, `0x3415`, `0x66`). `mcycle` is the timing
source.

`make -C eriscv-m2/sw coremark` builds the default one-iteration
simulation smoke. `tools/run_coremark_sim.py` uses its automatic backend
(Verilator when available, otherwise ModelSim) and reports the measured
`mcycle` delta encoded in `eriscv_coremark_result`.

The smoke verifies CoreMark CRCs but is deliberately shorter than CoreMark's
10-second reporting requirement. It is evidence of functional porting and
cycle collection only, not an official CoreMark score or CoreMark/MHz claim.
