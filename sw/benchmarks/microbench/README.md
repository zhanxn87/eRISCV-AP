# eRISCV M2 microbench

The benchmark reports total `mcycle` and `minstret` deltas for 256-iteration
ALU, branch, DTCM load/store, MUL, DIV, and `fence.i` loops. It also reports
the raw cycle delta from arming an `ecall`, CLINT/WFI wake, and APB-timer/PLIC
interrupt to the first instruction of its M-mode handler. These are product
simulation baselines, not architectural CPI claims.

Run `python3 eriscv-m2/sw/tools/run_microbench_sim.py` to build, run
the ModelSim path, and print the checked-in report layout.
