#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Build and simulator-check one M2 Embench-IoT workload."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SW_DIR = ROOT / "eriscv-m2/sw"
SIM_DIR = ROOT / "eriscv-m2/dv/soc/sim"
TOOLS_DIR = ROOT / "tools"
sys.path.insert(0, str(TOOLS_DIR / "project"))
sys.path.insert(0, str(TOOLS_DIR / "sim"))

from elf_to_mem import elf_entry_point
from resolve_filelist import write_resolved_filelist
from sim_backend import (
    build_verilator,
    default_vsim,
    path_for_vsim,
    run_modelsim,
    run_verilator,
    select_backend,
)

DMEM_BASE = 0x11000000
RESULT_SYMBOL = "eriscv_embench_result"
PASS_MARKER = "ERISCV_M2_SOC PASS:"
FAIL_MARKERS = ("ERISCV_M2_SOC FAIL:", "TB ERROR:", "** Error:", "** Fatal:", "Fatal:")
EMBENCH_SUITE = (
    "matmult-int", "crc32", "huffbench", "sglib-combined", "slre", "qrduino",
    "aha-mont64", "minver", "nettle-aes", "nettle-sha256", "picojpeg", "wikisort",
)
WIKISORT_MAX_CYCLES = 4_000_000


def result_word_index(elf: Path) -> int:
    result = subprocess.run(
        ["riscv64-unknown-elf-nm", "-n", str(elf)], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True,
    )
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[2] == RESULT_SYMBOL:
            address = int(fields[0], 16)
            if address < DMEM_BASE or (address & 3) != 0:
                raise RuntimeError(f"{RESULT_SYMBOL} is not an aligned DTCM address: 0x{address:08x}")
            return (address - DMEM_BASE) >> 2
    raise RuntimeError(f"ELF does not define {RESULT_SYMBOL}")


def run_suite(args: argparse.Namespace) -> int:
    passed = 0
    for bench in EMBENCH_SUITE:
        max_cycles = WIKISORT_MAX_CYCLES if bench == "wikisort" else args.max_cycles
        command = [
            sys.executable, str(Path(__file__).resolve()), "--bench", bench,
            "--profile", args.profile, "--scale", str(args.scale),
            "--max-cycles", str(max_cycles), "--backend", args.backend,
            "--vsim", args.vsim, "--verilator", args.verilator,
        ]
        if subprocess.run(command).returncode == 0:
            passed += 1
    failed = len(EMBENCH_SUITE) - passed
    state = "PASS" if failed == 0 else "FAIL"
    print(f"EMBENCH SUITE {state}: total={len(EMBENCH_SUITE)} passed={passed} failed={failed}")
    return 0 if failed == 0 else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bench", default="matmult-int")
    parser.add_argument("--profile", choices=("speed", "size"), default="speed")
    parser.add_argument("--scale", type=int, default=1)
    parser.add_argument("--max-cycles", type=int, default=2_000_000)
    parser.add_argument("--suite", action="store_true", help="run the qualified 12-workload speed suite")
    parser.add_argument("--backend", choices=("auto", "modelsim", "verilator"), default="auto")
    parser.add_argument("--vsim", default=default_vsim())
    parser.add_argument("--verilator", default="verilator")
    args = parser.parse_args()
    if args.max_cycles <= 0 or args.scale <= 0:
        parser.error("max-cycles and scale must be positive")
    if args.suite:
        return run_suite(args)

    subprocess.run(
        ["make", "-B", "-C", str(SW_DIR), "embench",
         f"EMBENCH_BENCH={args.bench}", f"EMBENCH_PROFILE={args.profile}",
         f"EMBENCH_SCALE={args.scale}"],
        check=True,
    )
    build_dir = SW_DIR / "build/embench" / args.profile / args.bench / f"scale-{args.scale}"
    elf = build_dir / f"{args.bench}.elf"
    imem = build_dir / f"{args.bench}.imem.mem"
    dmem = build_dir / f"{args.bench}.dmem.mem"
    if args.profile == "size":
        size = subprocess.run(
            ["riscv64-unknown-elf-size", "-A", str(elf)], text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True,
        ).stdout
        print(f"EMBENCH SIZE PASS: bench={args.bench} scale={args.scale}")
        print(size, end="")
        return 0
    result_index = result_word_index(elf)
    log_path = build_dir / f"{args.bench}.sim.log"

    write_resolved_filelist(SIM_DIR / "filelist.f", SIM_DIR / "file.list")
    backend = select_backend(args.backend, args.vsim, args.verilator)
    plusargs = [
        f"+tc=EMBENCH-{args.bench.upper()}-{args.profile.upper()}",
        f"+instr_mem_file={imem.resolve().as_posix()}",
        f"+data_mem_file={dmem.resolve().as_posix()}",
        f"+boot_addr={elf_entry_point(elf):x}",
        f"+tohost_addr={result_index:x}",
        "+expected_tohost=80000000",
        "+expected_tohost_mask=c0000000",
        f"+max_cycles={args.max_cycles}",
    ]
    if backend == "modelsim":
        command = (
            "if {![file exists work]} { vlib work }; "
            "vmap work work; "
            "vlog +acc -work work -incr -f file.list; "
            f"vsim -lib work -t 1ps +tc=EMBENCH-{args.bench.upper()}-{args.profile.upper()} "
            f"+instr_mem_file={path_for_vsim(args.vsim, imem)} "
            f"+data_mem_file={path_for_vsim(args.vsim, dmem)} "
            f"+boot_addr={elf_entry_point(elf):x} +tohost_addr={result_index:x} "
            "+expected_tohost=80000000 +expected_tohost_mask=c0000000 "
            f"+max_cycles={args.max_cycles} soc_tb; run -all; quit -f"
        )
        passed, reason, elapsed = run_modelsim(
            SIM_DIR, args.vsim, command, log_path, PASS_MARKER, FAIL_MARKERS
        )
    else:
        built, reason, binary = build_verilator(
            SIM_DIR, build_dir, args.verilator, "soc_tb",
            binary_name="Vsoc_tb_embench",
            # CVFPU drives stage 0 combinationally and later stages
            # sequentially; Verilator reports the non-overlapping packed
            # slices as BLKANDNBLK, as in the M2 core/benchmark runners.
            warning_suppresses=("BLKANDNBLK",),
            warnings_fatal=False,
        )
        if not built:
            print(f"EMBENCH SIM FAIL: {reason}", file=sys.stderr)
            return 1
        passed, reason, elapsed = run_verilator(
            binary, plusargs, log_path, PASS_MARKER, FAIL_MARKERS
        )
    if not passed:
        print(f"EMBENCH SIM FAIL: {reason}", file=sys.stderr)
        return 1
    match = re.search(r"TB INFO: tohost reached value=([0-9a-fA-F]+)",
                      log_path.read_text(encoding="utf-8"))
    if match is None:
        print("EMBENCH SIM FAIL: missing result word", file=sys.stderr)
        return 1
    result = int(match.group(1), 16)
    if (result & 0xc0000000) != 0x80000000:
        print(f"EMBENCH SIM FAIL: verification failed (result=0x{result:08x})", file=sys.stderr)
        return 1
    mcycle = result & 0x3fffffff
    print(f"EMBENCH SIM PASS: backend={backend} bench={args.bench} profile={args.profile} scale={args.scale} "
          f"mcycle={mcycle} mcycle_per_scale={mcycle / args.scale:.3f} wall_s={elapsed:.1f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
