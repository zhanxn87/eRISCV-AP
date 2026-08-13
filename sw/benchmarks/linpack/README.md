# M2 single-precision LINPACK-derived benchmark

This freestanding workload measures scalar LU factorization with partial
pivoting (`sgefa`) and back-substitution (`sgesl`) on M2's RV32F unit.  The
reported operation count is `2/3*N^3 + 2*N^2` per solve.  Matrix generation,
residual verification, report writes, and UART output are outside the mcycle
window.

It is **not** an official LINPACK score: the official historical benchmark
requires 64-bit arithmetic, while M2 implements binary32 RV32F.  Treat the
result as a reproducible M2 single-precision scalar-FPU datapoint only.

`N=32` is the default for cycle-accurate simulation.  `N=100` is the classic
matrix order, but its scalar CVFPU simulation is intentionally a manual,
long-running test better suited to FPGA measurement.

```sh
# Verilator functional/performance run (default N=32, one solve)
make -C eriscv-m2/sw sim-linpack

# Fast smoke
make -C eriscv-m2/sw sim-linpack LINPACK_ORDER=16

# Classic N=100 image for a board or long-running simulation
make -C eriscv-m2/sw linpack LINPACK_ORDER=100 LINPACK_REPETITIONS=1
```

The runner prints raw mcycle count, cycles/solve, calculated MFLOPS/MHz,
MFLOPS at 100 MHz, residual, and FCSR exception flags.  It builds with the
M2 software contract (`rv32imfc_zicsr_zifencei_zicntr_zihpm_zihintpause_zba_zbb_zbs_zcf`,
`ilp32f`, `-O2`, and `-ffp-contract=off`).
