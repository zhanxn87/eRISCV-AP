#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Build and ModelSim-check the M2 mcycle counter with fixed NOP windows."""

from __future__ import annotations

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
RESULT_SYMBOL = "eriscv_mcycle_counter_report"
PASS_RESULT = 0x80000001
REPORT_MAGIC = 0x4D435931
NOP_COUNT = 8192
REPORT_WORDS = 8
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
    subprocess.run(
        ["make", "-B", "-C", str(SW_DIR), "EXAMPLE=mcycle_counter", "images"],
        check=True,
    )
    build_dir = SW_DIR / "build/mcycle_counter"
    elf = build_dir / "mcycle_counter.elf"
    imem = build_dir / "mcycle_counter.imem.mem"
    dmem = build_dir / "mcycle_counter.dmem.mem"
    result_index = result_word_index(elf)
    log_path = build_dir / "mcycle_counter.sim.log"

    write_resolved_filelist(SIM_DIR / "filelist.f", SIM_DIR / "file.list")
    command = (
        "if {![file exists work]} { vlib work }; vmap work work; "
        "vlog +acc -work work -incr -f file.list; "
        "vsim -lib work -t 1ps +tc=MCYCLE-COUNTER "
        f"+instr_mem_file={path_for_vsim(default_vsim(), imem)} "
        f"+data_mem_file={path_for_vsim(default_vsim(), dmem)} "
        f"+boot_addr={elf_entry_point(elf):x} +tohost_addr={result_index:x} "
        f"+expected_tohost={PASS_RESULT:x} "
        f"+report_words_base={result_index:x} +report_words_count={REPORT_WORDS} "
        "+max_cycles=50000 soc_tb; run -all; quit -f"
    )
    passed, reason, elapsed = run_modelsim(
        SIM_DIR, default_vsim(), command, log_path, PASS_MARKER, FAIL_MARKERS
    )
    report = {
        int(index): int(value, 16)
        for index, value in re.findall(
            r"TB REPORT: word\[(\d+)\]=([0-9a-fA-F]+)",
            log_path.read_text(encoding="utf-8"),
        )
    }
    if (not passed or report.get(0) != PASS_RESULT or
            report.get(1) != REPORT_MAGIC or report.get(2) != NOP_COUNT or
            report.get(6, 0) < NOP_COUNT or report.get(7, 0) < NOP_COUNT):
        print(f"MCYCLE COUNTER SIM FAIL: {reason}; report={report}", file=sys.stderr)
        return 1

    print(
        "MCYCLE COUNTER SIM PASS: "
        f"start={report[3]} middle={report[4]} stop={report[5]} "
        f"delta0={report[6]} delta1={report[7]} wall_s={elapsed:.1f}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
