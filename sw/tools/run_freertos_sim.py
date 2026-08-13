#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Build and ModelSim-check the M2 static FreeRTOS M-mode timing profile."""

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
RESULT_SYMBOL = "eriscv_freertos_result"
TIMING_REPORT_SYMBOL = "eriscv_freertos_timing_report"
TIMING_REPORT_WORDS = 10
TIMING_REPORT_MAGIC = 0x46525432
FAILSTOP_RESULT = 0xDEAD0001
PASS_MARKER = "ERISCV_M2_SOC PASS:"
FAIL_MARKERS = ("ERISCV_M2_SOC FAIL:", "TB ERROR:", "** Error:", "** Fatal:", "Fatal:")
REPORT_NAMES = (
    "magic",
    "yield_a_before",
    "yield_b_entry",
    "yield_b_before",
    "yield_a_resume",
    "timeslice_tick",
    "timeslice_b_entry",
    "timer_arm",
    "plic_isr_entry",
    "consumer_wake",
)


def symbol_word_index(elf: Path, symbol: str) -> int:
    result = subprocess.run(
        ["riscv64-unknown-elf-nm", "-n", str(elf)], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True,
    )
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[2] == symbol:
            address = int(fields[0], 16)
            if address < DMEM_BASE or (address & 3) != 0:
                raise RuntimeError(f"{symbol} is not an aligned DTCM address: 0x{address:08x}")
            return (address - DMEM_BASE) >> 2
    raise RuntimeError(f"ELF does not define {symbol}")


def parse_timing_report(log_path: Path) -> tuple[dict[str, int], int]:
    text = log_path.read_text(encoding="utf-8")
    report_matches = re.findall(r"TB REPORT: word\[(\d+)\]=([0-9a-fA-F]+)", text)
    report_words = {
        int(index): int(value, 16)
        for index, value in report_matches
        if 0 <= int(index) < TIMING_REPORT_WORDS
    }
    if len(report_words) != TIMING_REPORT_WORDS:
        raise RuntimeError("timing report ABI missing or corrupt")
    report = {name: report_words[index] for index, name in enumerate(REPORT_NAMES)}
    if report["magic"] != TIMING_REPORT_MAGIC:
        raise RuntimeError("timing report ABI magic mismatch")
    missing = [name for name in REPORT_NAMES[1:] if report[name] == 0]
    if missing:
        raise RuntimeError(f"timing report boundary missing: {', '.join(missing)}")

    source_match = re.search(
        r"TB PLIC SOURCE ASSERT: source=\d+ mcycle=([0-9a-fA-F]+)", text
    )
    if source_match is None:
        raise RuntimeError("TB PLIC source assertion boundary missing")
    source_mcycle = int(source_match.group(1), 16)
    if source_mcycle == 0:
        raise RuntimeError("TB PLIC source assertion mcycle is zero")
    return report, source_mcycle


def delta(later: int, earlier: int) -> int:
    return (later - earlier) & 0xFFFFFFFF


def metric_set(report: dict[str, int], source_mcycle: int) -> dict[str, int]:
    return {
        "yield_a_to_b": delta(report["yield_b_entry"], report["yield_a_before"]),
        "yield_b_to_a": delta(report["yield_a_resume"], report["yield_b_before"]),
        "tick_to_b": delta(report["timeslice_b_entry"], report["timeslice_tick"]),
        "plic_source_to_isr": delta(report["plic_isr_entry"], source_mcycle),
        "isr_to_consumer_wake": delta(
            report["consumer_wake"], report["plic_isr_entry"]
        ),
    }


def print_table(title: str, rows: list[tuple[str, str]], value_header: str = "Result") -> None:
    width = max(len(name) for name, _ in rows)
    print(title)
    print(f"  {'Check':<{width}}  {value_header}")
    print(f"  {'-' * width}  {'-' * len(value_header)}")
    for name, value in rows:
        print(f"  {name:<{width}}  {value}")


def build_images(cpp_define: str | None = None) -> None:
    command = ["make", "-B", "-C", str(SW_DIR / "rtos/freertos"), "images"]
    if cpp_define is not None:
        command.append(f"CPPFLAGS=-D{cpp_define}")
    subprocess.run(command, check=True)


def run_failstop_test(args: argparse.Namespace, name: str, cpp_define: str) -> None:
    build_images(cpp_define)
    build_dir = SW_DIR / "build/freertos"
    elf = build_dir / "freertos_mmode.elf"
    imem = build_dir / "freertos_mmode.imem.mem"
    dmem = build_dir / "freertos_mmode.dmem.mem"
    result_index = symbol_word_index(elf, RESULT_SYMBOL)
    log_path = build_dir / f"freertos_mmode.{name}.sim.log"
    command = (
        "if {![file exists work]} { vlib work }; "
        "vmap work work; "
        "vlog +acc -work work -incr -f file.list; "
        f"vsim -lib work -t 1ps +tc=FREERTOS-MMODE-{name.upper()} "
        f"+instr_mem_file={path_for_vsim(args.vsim, imem)} "
        f"+data_mem_file={path_for_vsim(args.vsim, dmem)} "
        f"+boot_addr={elf_entry_point(elf):x} +tohost_addr={result_index:x} "
        f"+expected_tohost={FAILSTOP_RESULT:x} "
        f"+max_cycles={args.max_cycles} soc_tb; run -all; quit -f"
    )
    passed, reason, elapsed = run_modelsim(
        SIM_DIR, args.vsim, command, log_path, PASS_MARKER, FAIL_MARKERS
    )
    if not passed:
        raise RuntimeError(f"{name}: {reason}")
    text = log_path.read_text(encoding="utf-8")
    match = re.search(r"TB INFO: tohost reached value=([0-9a-fA-F]+)", text)
    if match is None or int(match.group(1), 16) != FAILSTOP_RESULT:
        raise RuntimeError(f"{name}: expected fail-stop result 0x{FAILSTOP_RESULT:08x}")
    print(f"FREERTOS FAIL-STOP PASS: {name} wall_s={elapsed:.1f}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--max-cycles", type=int, default=500_000)
    parser.add_argument("--runs", type=int, default=1,
                        help="repeat the simulation and require identical timing metrics")
    parser.add_argument("--failstops", action="store_true",
                        help="run injected assert and stack-overflow fail-stop checks")
    parser.add_argument("--skip-failstops", dest="failstops", action="store_false",
                        help=argparse.SUPPRESS)
    parser.add_argument("--vsim", default=default_vsim())
    args = parser.parse_args()
    if args.max_cycles <= 0:
        parser.error("max-cycles must be positive")
    if args.runs <= 0:
        parser.error("runs must be positive")

    build_images()
    build_dir = SW_DIR / "build/freertos"
    elf = build_dir / "freertos_mmode.elf"
    imem = build_dir / "freertos_mmode.imem.mem"
    dmem = build_dir / "freertos_mmode.dmem.mem"
    result_index = symbol_word_index(elf, RESULT_SYMBOL)
    timing_report_index = symbol_word_index(elf, TIMING_REPORT_SYMBOL)
    write_resolved_filelist(SIM_DIR / "filelist.f", SIM_DIR / "file.list")

    metric_runs: list[dict[str, int]] = []
    for run_index in range(args.runs):
        log_path = build_dir / (
            "freertos_mmode.sim.log"
            if args.runs == 1
            else f"freertos_mmode.run{run_index + 1}.sim.log"
        )
        command = (
            "if {![file exists work]} { vlib work }; "
            "vmap work work; "
            "vlog +acc -work work -incr -f file.list; "
            "vsim -lib work -t 1ps +tc=FREERTOS-MMODE "
            f"+instr_mem_file={path_for_vsim(args.vsim, imem)} "
            f"+data_mem_file={path_for_vsim(args.vsim, dmem)} "
            f"+boot_addr={elf_entry_point(elf):x} "
            f"+tohost_addr={result_index:x} +report_words_base={timing_report_index:x} "
            "+expected_tohost=1 "
            f"+report_words_count={TIMING_REPORT_WORDS} +report_plic_timer_source "
            "+spi_miso_byte=3c +expected_spi_tx=a5 +spi_transfer_count=3 "
            f"+max_cycles={args.max_cycles} soc_tb; run -all; quit -f"
        )
        passed, reason, elapsed = run_modelsim(
            SIM_DIR, args.vsim, command, log_path, PASS_MARKER, FAIL_MARKERS
        )
        if not passed:
            print(f"FREERTOS SIM FAIL: run={run_index + 1} {reason}", file=sys.stderr)
            return 1

        text = log_path.read_text(encoding="utf-8")
        match = re.search(r"TB INFO: tohost reached value=([0-9a-fA-F]+)", text)
        if match is None or int(match.group(1), 16) != 1:
            print("FREERTOS SIM FAIL: expected result word 0x00000001", file=sys.stderr)
            return 1
        try:
            report, source_mcycle = parse_timing_report(log_path)
        except RuntimeError as error:
            print(f"FREERTOS SIM FAIL: run={run_index + 1} {error}", file=sys.stderr)
            return 1
        metrics = metric_set(report, source_mcycle)
        if any(value == 0 for value in metrics.values()):
            print(f"FREERTOS SIM FAIL: run={run_index + 1} zero timing delta", file=sys.stderr)
            return 1
        metric_runs.append(metrics)
        print(f"FREERTOS SIM PASS: static M-mode timing profile run={run_index + 1} "
              f"wall_s={elapsed:.1f}")

    if any(metrics != metric_runs[0] for metrics in metric_runs[1:]):
        print("FREERTOS SIM FAIL: timing metrics differ across runs", file=sys.stderr)
        return 1
    if args.runs > 1:
        print(f"FREERTOS TIMING CONSISTENT: runs={args.runs}")
    failstop_assert = "SKIPPED"
    failstop_stack_overflow = "SKIPPED"
    if args.failstops:
        try:
            run_failstop_test(args, "assert", "FREERTOS_FORCE_ASSERT")
            run_failstop_test(args, "stack-overflow", "FREERTOS_FORCE_STACK_OVERFLOW")
        except RuntimeError as error:
            print(f"FREERTOS SIM FAIL: {error}", file=sys.stderr)
            return 1
        build_images()
        failstop_assert = "PASS"
        failstop_stack_overflow = "PASS"
    print_table("FREERTOS SUMMARY: PASS", [
        ("normal profile runs", str(args.runs)),
        ("static tasks / scheduler", "PASS"),
        ("yield and time slicing", "PASS"),
        ("heap_4 allocation", "PASS"),
        ("SPI polling and async", "PASS"),
        ("static mutex", "PASS"),
        ("one-slot queue mailbox", "PASS"),
        ("APB timer to PLIC", "PASS"),
        ("queue notification wake", "PASS"),
        ("timing report ABI", "PASS"),
        ("injected configASSERT fail-stop", failstop_assert),
        ("injected stack-overflow fail-stop", failstop_stack_overflow),
    ])
    print_table(
        "FREERTOS TIMING (mcycle)",
        [(name, str(value)) for name, value in metric_runs[0].items()],
        "Cycles",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
