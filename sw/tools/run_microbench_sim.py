#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Build and ModelSim-run the M2 eRISCV microbench."""

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
RESULT_SYMBOL = "eriscv_microbench_report"
REPORT_WORDS = 19
WORK_SIGNATURE = 0x010306C9
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
    parser.add_argument("--max-cycles", type=int, default=100_000)
    parser.add_argument("--vsim", default=default_vsim())
    args = parser.parse_args()
    subprocess.run(["make", "-B", "-C", str(SW_DIR / "benchmarks/microbench"), "images"], check=True)
    build_dir = SW_DIR / "build/microbench"
    elf = build_dir / "microbench.elf"
    imem = build_dir / "microbench.imem.mem"
    dmem = build_dir / "microbench.dmem.mem"
    result_index = result_word_index(elf)
    log_path = build_dir / "microbench.sim.log"
    write_resolved_filelist(SIM_DIR / "filelist.f", SIM_DIR / "file.list")
    command = (
        "if {![file exists work]} { vlib work }; vmap work work; "
        "vlog +acc -work work -incr -f file.list; "
        "vsim -lib work -t 1ps +tc=MICROBENCH "
        f"+instr_mem_file={path_for_vsim(args.vsim, imem)} "
        f"+data_mem_file={path_for_vsim(args.vsim, dmem)} "
        f"+boot_addr={elf_entry_point(elf):x} +tohost_addr={result_index:x} "
        "+expected_tohost=1 "
        f"+report_words_base={result_index:x} +report_words_count={REPORT_WORDS} "
        f"+max_cycles={args.max_cycles} soc_tb; run -all; quit -f"
    )
    passed, reason, elapsed = run_modelsim(SIM_DIR, args.vsim, command, log_path, PASS_MARKER, FAIL_MARKERS)
    report = {int(index): int(value, 16) for index, value in re.findall(r"TB REPORT: word\[(\d+)\]=([0-9a-fA-F]+)", log_path.read_text(encoding="utf-8"))}
    if (not passed or report.get(0) != 1 or report.get(1) != 0x4D425031 or
            report.get(2) != 256 or report.get(18) != WORK_SIGNATURE):
        print(f"MICROBENCH SIM FAIL: {reason}", file=sys.stderr)
        return 1
    labels = ("alu", "branch", "load_store", "mul", "div", "fence_i", "ecall", "clint_wfi", "plic_service")
    values = [report[index] for index in range(3, 12)]
    print("MICROBENCH SIM PASS: " + " ".join(f"{label}={value}" for label, value in zip(labels, values)) +
          f" loop_iterations={report[2]} " +
          " ".join(f"{label}_cycles_per_iteration={value / report[2]:.3f}"
                   for label, value in zip(labels[:6], values[:6])) +
          f" work_signature=0x{report[18]:08x} wall_s={elapsed:.1f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
