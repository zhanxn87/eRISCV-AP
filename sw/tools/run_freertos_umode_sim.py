#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Build and ModelSim-check the M2 four-task FreeRTOS U-mode/PMP smoke."""

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
RESULT_SYMBOL = "eriscv_freertos_umode_result"
TIMING_SYMBOL = "eriscv_umode_timing_report"
TIMING_WORD_COUNT = 11  # magic + 10 mcycle fields
FAIL_STOP_VALUE = 0xDEAD0001
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


def timing_word_index(elf: Path) -> int:
    output = subprocess.run(
        ["riscv64-unknown-elf-nm", "-n", str(elf)], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True,
    ).stdout
    for line in output.splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[2] == TIMING_SYMBOL:
            address = int(fields[0], 16)
            return (address - DMEM_BASE) >> 2
    raise RuntimeError(f"ELF does not define {TIMING_SYMBOL}")


TIMING_FIELDS = [
    "yield_a_before", "yield_b_entry", "yield_b_before", "yield_a_resume",
    "delay_before", "delay_after", "notify_before", "notify_after",
    "wait_before", "wait_after",
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--max-cycles", type=int, default=2_000_000)
    parser.add_argument("--vsim", default=default_vsim())
    parser.add_argument("--bad-syscall", action="store_true",
                        help="expect the U-mode unknown-service fail-stop path")
    parser.add_argument("--pmp-negative", action="store_true",
                        help="expect the PMP negative-registration fail-stop path")
    args = parser.parse_args()
    if args.bad_syscall and args.pmp_negative:
        parser.error("--bad-syscall and --pmp-negative are mutually exclusive")
    mode = "pmp_negative" if args.pmp_negative else ("bad_syscall" if args.bad_syscall else "default")
    build_dir = SW_DIR / "build" / f"freertos_umode_{mode}" if mode != "default" else SW_DIR / "build" / "freertos_umode"
    make_command = ["make", "-B", "-C", str(SW_DIR / "rtos/freertos_umode"), "images"]
    if args.bad_syscall:
        make_command.append("EXTRA_CFLAGS=-DERISCV_UMODE_BAD_SYSCALL_TEST")
        make_command.append(f"BUILD_DIR={build_dir}")
    elif args.pmp_negative:
        make_command.append("EXTRA_CFLAGS=-DERISCV_UMODE_PMP_NEGATIVE_TEST")
        make_command.append(f"BUILD_DIR={build_dir}")
    subprocess.run(make_command, check=True)
    elf = build_dir / "freertos_umode.elf"
    imem = build_dir / "freertos_umode.imem.mem"
    dmem = build_dir / "freertos_umode.dmem.mem"
    result_index = result_word_index(elf)
    timing_index = timing_word_index(elf)
    expected_value = FAIL_STOP_VALUE if (args.bad_syscall or args.pmp_negative) else 1
    log_path = build_dir / "freertos_umode.sim.log"
    write_resolved_filelist(SIM_DIR / "filelist.f", SIM_DIR / "file.list")
    command = (
        "if {![file exists work]} { vlib work }; vmap work work; "
        "vlog +acc -work work -incr -f file.list; "
        "vsim -lib work -t 1ps +tc=FREERTOS-UMODE "
        f"+instr_mem_file={path_for_vsim(args.vsim, imem)} "
        f"+data_mem_file={path_for_vsim(args.vsim, dmem)} "
        f"+boot_addr={elf_entry_point(elf):x} +tohost_addr={result_index:x} "
        f"+expected_tohost={expected_value:x} "
        f"+report_words_base={timing_index:x} +report_words_count={TIMING_WORD_COUNT} "
        f"+max_cycles={args.max_cycles} soc_tb; run -all; quit -f"
    )
    passed, reason, elapsed = run_modelsim(SIM_DIR, args.vsim, command, log_path, PASS_MARKER, FAIL_MARKERS)
    log_text = log_path.read_text(encoding="utf-8")
    match = re.search(r"TB INFO: tohost reached value=([0-9a-fA-F]+)", log_text)
    if not passed or match is None or int(match.group(1), 16) != expected_value:
        print(f"FREERTOS UMODE SIM FAIL: {reason}", file=sys.stderr)
        return 1
    if args.bad_syscall:
        print(f"FREERTOS UMODE SIM PASS: unknown U syscall fail-stop wall_s={elapsed:.1f}")
        return 0
    if args.pmp_negative:
        print(f"FREERTOS UMODE SIM PASS: PMP negative-registration fail-stop wall_s={elapsed:.1f}")
        return 0
    print(f"FREERTOS UMODE SIM PASS: four U tasks + PMP reload/isolation wall_s={elapsed:.1f}")

    # Extract timing report words from TB REPORT lines
    report_pattern = re.compile(r"TB REPORT: word\[(\d+)\]=([0-9a-fA-F]+)")
    timing_words: dict[int, int] = {}
    for m in report_pattern.finditer(log_text):
        timing_words[int(m.group(1))] = int(m.group(2), 16)
    if len(timing_words) != TIMING_WORD_COUNT:
        print(f"  [WARN] timing report: got {len(timing_words)} words, expected {TIMING_WORD_COUNT}", file=sys.stderr)
        return 0
    magic = timing_words[0]
    if magic != 0x554D5431:
        print(f"  [WARN] timing report magic mismatch: 0x{magic:08x}", file=sys.stderr)
        return 0
    vals = {TIMING_FIELDS[i]: timing_words[i + 1] for i in range(len(TIMING_FIELDS))}
    print(f"  P9.2 U-mode scheduler timing (mcycle, 100 MHz):")
    for name in TIMING_FIELDS:
        print(f"    {name:20s}: {vals[name]:>10d}")
    print()
    # Derived metrics
    if vals["yield_a_before"] and vals["yield_b_entry"]:
        print(f"    voluntary-yield latency : {vals['yield_b_entry'] - vals['yield_a_before']:>5d} cycles")
    if vals["delay_before"] and vals["delay_after"]:
        print(f"    delay(3) wall-clock     : {vals['delay_after'] - vals['delay_before']:>5d} cycles")
    if vals["notify_before"] and vals["notify_after"]:
        print(f"    notify_give sync cost   : {vals['notify_after'] - vals['notify_before']:>5d} cycles")
    if vals["wait_before"] and vals["wait_after"]:
        print(f"    notify_wait wall-clock  : {vals['wait_after'] - vals['wait_before']:>5d} cycles")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
