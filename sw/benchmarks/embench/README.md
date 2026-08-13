# M2 Embench-IoT Adapter

This adapter leaves the pinned upstream `embench-iot` submodule unchanged. It
links a selected workload with the M2 BSP, records its verified `mcycle`
delta in `eriscv_embench_result`, and emits standard IMEM/DTCM images.

Run the qualified 12-workload speed suite locally:

```sh
make -C eriscv-m2/sw embench-suite
```

The suite is `matmult-int`, `crc32`, `huffbench`, `sglib-combined`, `slre`,
`qrduino`, `aha-mont64`, `minver`, `nettle-aes`, `nettle-sha256`, `picojpeg`,
and `wikisort`. `wikisort` uses a 4,000,000-cycle cap; the other workloads
use the standard 2,000,000-cycle cap.

Build a speed image:

```sh
make -C eriscv-m2/sw embench EMBENCH_BENCH=matmult-int EMBENCH_PROFILE=speed EMBENCH_SCALE=1
```

Build the corresponding size image:

```sh
make -C eriscv-m2/sw embench EMBENCH_BENCH=matmult-int EMBENCH_PROFILE=size EMBENCH_SCALE=1
```

`CPU_MHZ=1`, `WARMUP_HEAT=0`, and `EMBENCH_SCALE=1` are fixed simulation-profile
settings. The adapter derives generated workload sources in `build/`, replaces
the upstream local repeat count, and adds the missing standard `stdbool.h`
include for wikisort under GCC 15.3's GNU C23 default; the pinned submodule
remains unchanged. These simulation measurements are not Embench reference scores or
wall-time measurements. Speed runs execute the selected simulator and verify the workload;
Size runs build the `-Os` image and report ELF sections without simulation.
The speed suite is an engineering simulation regression, not an upstream
normalized Embench score.
