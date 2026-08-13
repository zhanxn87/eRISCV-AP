#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Build and measure the M2 single-precision LINPACK-derived workload."""

from __future__ import annotations

import argparse
import re
import struct
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
from sim_backend import build_verilator, default_vsim, path_for_vsim, run_modelsim, run_verilator, select_backend

DMEM_BASE = 0x11000000
RESULT_SYMBOL = "eriscv_linpack_sp_report"
REPORT_MAGIC = 0x4C504631
REPORT_PASS = 0x80000001
REPORT_WORDS = 9
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


def float_from_bits(bits: int) -> float:
    return struct.unpack("<f", struct.pack("<I", bits))[0]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--order", type=int, choices=(16, 32, 100), default=32)
    parser.add_argument("--repetitions", type=int, default=1)
    parser.add_argument("--max-cycles", type=int, default=3_000_000)
    parser.add_argument("--backend", choices=("auto", "modelsim", "verilator"), default="auto")
    parser.add_argument("--vsim", default=default_vsim())
    parser.add_argument("--verilator", default="verilator")
    args = parser.parse_args()
    if args.repetitions <= 0 or args.max_cycles <= 0:
        parser.error("repetitions and max-cycles must be positive")

    subprocess.run(
        ["make", "-B", "-C", str(SW_DIR / "benchmarks/linpack"), "images",
         f"SW_DIR={SW_DIR}", f"ORDER={args.order}", f"REPETITIONS={args.repetitions}"],
        check=True,
    )
    build_dir = SW_DIR / "build/linpack" / f"n{args.order}-r{args.repetitions}"
    elf = build_dir / "linpack_sp.elf"
    result_index = result_word_index(elf)
    imem = build_dir / "linpack_sp.imem.mem"
    dmem = build_dir / "linpack_sp.dmem.mem"
    log_path = build_dir / "linpack_sp.sim.log"

    write_resolved_filelist(SIM_DIR / "filelist.f", SIM_DIR / "file.list")
    backend = select_backend(args.backend, args.vsim, args.verilator)
    plusargs = [
        f"+tc=LINPACK-SP-N{args.order}",
        f"+instr_mem_file={imem.resolve().as_posix()}",
        f"+data_mem_file={dmem.resolve().as_posix()}",
        f"+boot_addr={elf_entry_point(elf):x}",
        f"+tohost_addr={result_index:x}",
        f"+expected_tohost={REPORT_PASS:x}",
        f"+report_words_base={result_index:x}",
        f"+report_words_count={REPORT_WORDS}",
        f"+max_cycles={args.max_cycles}",
    ]
    if backend == "modelsim":
        command = (
            "if {![file exists work]} { vlib work }; vmap work work; "
            "vlog +acc -work work -incr -f file.list; "
            "vsim -lib work -t 1ps " + " ".join(plusargs[:1]) + " "
            f"+instr_mem_file={path_for_vsim(args.vsim, imem)} "
            f"+data_mem_file={path_for_vsim(args.vsim, dmem)} "
            f"+boot_addr={elf_entry_point(elf):x} +tohost_addr={result_index:x} "
            f"+expected_tohost={REPORT_PASS:x} +report_words_base={result_index:x} "
            f"+report_words_count={REPORT_WORDS} +max_cycles={args.max_cycles} "
            "soc_tb; run -all; quit -f"
        )
        passed, reason, elapsed = run_modelsim(SIM_DIR, args.vsim, command, log_path, PASS_MARKER, FAIL_MARKERS)
    else:
        built, reason, binary = build_verilator(
            SIM_DIR, build_dir, args.verilator, "soc_tb", binary_name="Vsoc_tb_linpack_sp",
            warning_suppresses=("BLKANDNBLK",), warnings_fatal=False,
        )
        if not built:
            print(f"LINPACK SP SIM FAIL: {reason}", file=sys.stderr)
            return 1
        passed, reason, elapsed = run_verilator(binary, plusargs, log_path, PASS_MARKER, FAIL_MARKERS)

    report = {int(index): int(value, 16) for index, value in re.findall(
        r"TB REPORT: word\[(\d+)\]=([0-9a-fA-F]+)", log_path.read_text(encoding="utf-8"))}
    cycles = report.get(6, 0)
    valid = (report.get(0) == REPORT_PASS and report.get(1) == REPORT_MAGIC and
             report.get(2) == args.order and report.get(3) == args.repetitions and cycles != 0)
    if not passed or not valid:
        print(f"LINPACK SP SIM FAIL: {reason}; report={report}", file=sys.stderr)
        return 1

    ops_per_solve = ((2.0 * args.order * args.order * args.order) / 3.0 +
                     2.0 * args.order * args.order)
    total_ops = ops_per_solve * args.repetitions
    max_error = float_from_bits(report[7])
    print(
        "LINPACK SP SIM PASS: "
        f"backend={backend} order={args.order} repetitions={args.repetitions} "
        f"cycles={cycles} cycles_per_solve={cycles / args.repetitions:.3f} "
        f"ops_per_solve={ops_per_solve:.3f} mflops_per_mhz={total_ops / cycles:.6f} "
        f"mflops_at_100mhz={total_ops * 100 / cycles:.3f} "
        f"max_residual={max_error:.8g} fflags=0x{report.get(8, 0):02x} wall_s={elapsed:.1f}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
