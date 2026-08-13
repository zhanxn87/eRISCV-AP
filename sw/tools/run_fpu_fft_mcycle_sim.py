#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Measure the eRISCV-M2 FFT kernel with mcycle and a DTCM report."""

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
from sim_backend import default_vsim, path_for_vsim, run_modelsim

DMEM_BASE = 0x11000000
RESULT_SYMBOL = "eriscv_fpu_fft_report"
REPORT_MAGIC = 0x46505431
REPORT_PASS = 0x80000001
REPORT_WORDS = 8
PERF_LAYOUT_ALIGN_CFLAGS = "-falign-functions=4 -falign-loops=4 -falign-jumps=4"
PASS_MARKER = "ERISCV_M2_SOC PASS:"
FAIL_MARKERS = ("ERISCV_M2_SOC FAIL:", "TB ERROR:", "** Error:", "** Fatal:", "Fatal:")


def result_word_index(elf: Path) -> int:
    output = subprocess.run(
        ["riscv64-unknown-elf-nm", "-n", str(elf)], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True,
    ).stdout
    for line in output.splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[2] == RESULT_SYMBOL:
            address = int(fields[0], 16)
            if address < DMEM_BASE or (address & 3) != 0:
                raise RuntimeError(f"{RESULT_SYMBOL} is not an aligned DTCM address: 0x{address:08x}")
            return (address - DMEM_BASE) >> 2
    raise RuntimeError(f"ELF does not define {RESULT_SYMBOL}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--example", choices=("fpu_fft", "fpu_fft1024"), default="fpu_fft1024")
    parser.add_argument("--points", type=int, choices=(128, 1024), default=1024)
    parser.add_argument("--max-cycles", type=int, default=1_600_000)
    parser.add_argument("--perf-profile", action="store_true",
                        help="enable testbench-only performance diagnostics")
    parser.add_argument("--perf-profile-trace", type=Path,
                        help="write optional +perf_profile CSV trace (implies --perf-profile)")
    args = parser.parse_args()

    if args.perf_profile_trace:
        args.perf_profile = True

    expected_example = "fpu_fft" if args.points == 128 else "fpu_fft1024"
    if args.example != expected_example:
        parser.error("--example and --points must name the same FFT size")
    # Performance evidence must come from the requested source revision, not a
    # potentially stale image left in build/ by an earlier run.
    subprocess.run(
        ["make", "-B", "-C", str(SW_DIR), f"EXAMPLE={args.example}",
         f"PERF_LAYOUT_ALIGN_CFLAGS={PERF_LAYOUT_ALIGN_CFLAGS}", "images"],
        check=True,
    )
    build_dir = SW_DIR / "build" / args.example
    elf = build_dir / f"{args.example}.elf"
    result_index = result_word_index(elf)
    log_path = build_dir / f"{args.example}.mcycle.sim.log"

    perf_profile_args: list[str] = []
    if args.perf_profile:
        perf_profile_args.append("+perf_profile=1")
        if args.perf_profile_trace:
            perf_profile_args.append(
                f"+perf_profile_trace={path_for_vsim(default_vsim(), args.perf_profile_trace)}"
            )

    write_resolved_filelist(SIM_DIR / "filelist.f", SIM_DIR / "file.list")
    command = (
        "if {![file exists work]} { vlib work }; vmap work work; "
        "vlog +acc -work work -incr -f file.list; "
        f"vsim -lib work -t 1ps +tc=BSP-FPU-FFT{args.points}-MCYCLE "
        f"+instr_mem_file={path_for_vsim(default_vsim(), build_dir / f'{args.example}.imem.mem')} "
        f"+data_mem_file={path_for_vsim(default_vsim(), build_dir / f'{args.example}.dmem.mem')} "
        f"+boot_addr={elf_entry_point(elf):x} +tohost_addr={result_index:x} "
        f"+expected_tohost={REPORT_PASS:x} +report_words_base={result_index:x} "
        f"+report_words_count={REPORT_WORDS} +max_cycles={args.max_cycles} "
        f"{' '.join(perf_profile_args)} "
        "soc_tb; run -all; quit -f"
    )
    passed, reason, elapsed = run_modelsim(SIM_DIR, default_vsim(), command, log_path, PASS_MARKER, FAIL_MARKERS)
    report = {int(index): int(value, 16) for index, value in re.findall(
        r"TB REPORT: word\[(\d+)\]=([0-9a-fA-F]+)", log_path.read_text(encoding="utf-8"))}
    valid = (report.get(0) == REPORT_PASS and report.get(1) == REPORT_MAGIC and
             report.get(2) == args.points and report.get(6) == 0 and
             (report.get(7, 0) & 0x1) != 0 and report.get(5, 0) != 0)
    if not passed or not valid:
        print(f"FPU FFT MCYCLE SIM FAIL: {reason}; report={report}", file=sys.stderr)
        return 1
    print(f"FPU FFT MCYCLE SIM PASS: points={report[2]} start={report[3]} stop={report[4]} "
          f"fft_cycles={report[5]} fflags=0x{report[7]:02x} wall_s={elapsed:.1f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
