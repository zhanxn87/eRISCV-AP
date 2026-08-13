#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Build and simulator-check the M2 Dhrystone simulation smoke."""

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
from dhrystone_metrics import append_dhrystone_csv
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
RESULT_SYMBOL = "eriscv_dhrystone_result"
HPM_REPORT_SYMBOL = "eriscv_dhrystone_hpm_report"
HPM_REPORT_MAGIC = 0x44524859
HPM_REPORT_WORDS = 8
VAX_11_780_DHRYSTONES_PER_SECOND = 1757
PASS_MARKER = "ERISCV_M2_SOC PASS:"
FAIL_MARKERS = ("ERISCV_M2_SOC FAIL:", "TB ERROR:", "** Error:", "** Fatal:", "Fatal:")
DHRY_LAYOUT_ALIGN_CFLAGS = (
    "-falign-functions=4 -falign-loops=4 -falign-jumps=4"
)


def symbol_address(elf: Path, symbol: str) -> int:
    result = subprocess.run(
        ["riscv64-unknown-elf-nm", "-n", str(elf)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=True,
    )
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[2] == symbol:
            return int(fields[0], 16)
    raise RuntimeError(f"ELF does not define {symbol}")


def symbol_word_index(elf: Path, symbol: str) -> int:
    address = symbol_address(elf, symbol)
    if address < DMEM_BASE or (address & 3) != 0:
        raise RuntimeError(f"{symbol} is not an aligned DTCM address: 0x{address:08x}")
    return (address - DMEM_BASE) >> 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iterations", type=int, default=1000)
    parser.add_argument("--max-cycles", type=int, default=200_000_000)
    parser.add_argument("--hpm", action="store_true", help="enable diagnostic HPM reporting")
    parser.add_argument("--perf-profile", dest="perf_profile", action="store_true", default=True,
                        help="collect the benchmark-window SoC performance profile (default)")
    parser.add_argument("--no-perf-profile", dest="perf_profile", action="store_false",
                        help="disable TB diagnostics; the CSV row marks them unavailable")
    parser.add_argument("--perf-profile-trace", type=Path,
                        help="write optional per-event TB trace CSV")
    parser.add_argument("--results-csv", type=Path,
                        default=SW_DIR / "benchmarks/dhrystone/dmips_runs.csv",
                        help="append the successful result to this CSV")
    parser.add_argument("--backend", choices=("auto", "modelsim", "verilator"), default="auto")
    parser.add_argument("--vsim", default=default_vsim())
    parser.add_argument("--verilator", default="verilator")
    parser.add_argument("--disable-lmem-early-load", action="store_true",
                        help="run with EX-stage local-memory load launch disabled")
    parser.add_argument("--disable-load-response-bypass", action="store_true",
                        help="run with completed-load branch/store-data forwarding disabled")
    parser.add_argument("--disable-bht", action="store_true",
                        help="run with the dynamic BHT disabled (BTFNT remains active)")
    parser.add_argument("--disable-ras", action="store_true",
                        help="run with the return-address stack disabled")
    parser.add_argument("--disable-upper-32-prefetch", action="store_true",
                        help="disable sequential prefetch after an upper-halfword RV32 start")
    parser.add_argument("--layout-align", dest="layout_align", action="store_true", default=True,
                        help="compile with the standard 4-byte function/loop/jump alignment (default)")
    parser.add_argument("--no-layout-align", dest="layout_align", action="store_false",
                        help="reproduce archived unaligned compiler layout")
    args = parser.parse_args()
    if args.iterations <= 0 or args.max_cycles <= 0:
        parser.error("iterations and max-cycles must be positive")
    lmem_early_load_enabled = not args.disable_lmem_early_load
    load_response_bypass_enabled = not args.disable_load_response_bypass
    bht_enabled = not args.disable_bht
    ras_enabled = not args.disable_ras
    upper_32_prefetch_enabled = not args.disable_upper_32_prefetch
    layout_align_enabled = args.layout_align
    config_suffix = (
        f"lmem{int(lmem_early_load_enabled)}_"
        f"lrb{int(load_response_bypass_enabled)}_"
        f"bht{int(bht_enabled)}_ras{int(ras_enabled)}_"
        f"upref{int(upper_32_prefetch_enabled)}_layout4{int(layout_align_enabled)}"
    )
    build_name = "dhrystone-layout4" if layout_align_enabled else "dhrystone-unaligned"
    build_dir = SW_DIR / "build" / build_name

    subprocess.run(
        ["make", "-B", "-C", str(SW_DIR / "benchmarks/dhrystone"), "images",
         f"SW_DIR={SW_DIR}", f"ITERATIONS={args.iterations}", f"HPM={int(args.hpm)}",
         f"DHRY_EXTRA_CFLAGS={DHRY_LAYOUT_ALIGN_CFLAGS if layout_align_enabled else ''}",
         f"BUILD_DIR={build_dir}"],
        check=True,
    )
    elf = build_dir / "dhrystone.elf"
    imem = build_dir / "dhrystone.imem.mem"
    dmem = build_dir / "dhrystone.dmem.mem"
    result_index = symbol_word_index(elf, RESULT_SYMBOL)
    hpm_report_index = symbol_word_index(elf, HPM_REPORT_SYMBOL) if args.hpm else 0
    log_path = build_dir / f"dhrystone.{config_suffix}.sim.log"
    report_args = (
        f"+report_words_base={hpm_report_index:x} +report_words_count={HPM_REPORT_WORDS} "
        if args.hpm else ""
    )
    if args.perf_profile:
        profile_begin = symbol_address(elf, "eriscv_dhrystone_profile_begin")
        # M2's F-enabled build can place the inline end-label after the
        # stop-time function during code layout.  The stop-time entry is the
        # architectural end boundary itself (and equals the end-label in the
        # M0/M1 images), so use the function symbol directly.
        profile_end = symbol_address(elf, "dhry_port_stop_time")
        perf_profile_args = [
            "+perf_profile=1",
            f"+perf_profile_start_pc={profile_begin:x}",
            f"+perf_profile_stop_pc={profile_end:x}",
        ]
        if args.perf_profile_trace and args.perf_profile:
            perf_profile_args.append(
                f"+perf_profile_trace={args.perf_profile_trace.resolve().as_posix()}"
            )
    else:
        perf_profile_args = []

    write_resolved_filelist(SIM_DIR / "filelist.f", SIM_DIR / "file.list")
    backend = select_backend(args.backend, args.vsim, args.verilator)
    if backend == "modelsim":
        modelsim_perf_profile_args = perf_profile_args.copy()
        if args.perf_profile_trace:
            modelsim_perf_profile_args[-1] = (
                f"+perf_profile_trace={path_for_vsim(args.vsim, args.perf_profile_trace)}"
            )
        command = (
            "if {![file exists work]} { vlib work }; "
            "vmap work work; "
            "vlog +acc -work work -incr -f file.list; "
            "vsim -lib work -t 1ps "
            f"-gENABLE_LMEM_EARLY_LOAD_P={int(lmem_early_load_enabled)} "
            f"-gENABLE_LOAD_RESPONSE_BYPASS_P={int(load_response_bypass_enabled)} "
            f"-gENABLE_BHT_P={int(bht_enabled)} "
            f"-gENABLE_RAS_P={int(ras_enabled)} "
            f"-gENABLE_UPPER_32_PREFETCH_P={int(upper_32_prefetch_enabled)} "
            "+tc=DHRY-SMOKE "
            f"+instr_mem_file={path_for_vsim(args.vsim, imem)} "
            f"+data_mem_file={path_for_vsim(args.vsim, dmem)} "
            f"+boot_addr={elf_entry_point(elf):x} "
            f"+tohost_addr={result_index:x} "
            "+expected_tohost=80000000 +expected_tohost_mask=c0000000 "
            f"{report_args}"
            f"{' '.join(modelsim_perf_profile_args)} "
            f"+max_cycles={args.max_cycles} soc_tb; run -all; quit -f"
        )
        passed, reason, elapsed = run_modelsim(
            SIM_DIR, args.vsim, command, log_path, PASS_MARKER, FAIL_MARKERS
        )
    else:
        built, reason, binary = build_verilator(
            SIM_DIR, build_dir, args.verilator, "soc_tb",
            binary_name=f"Vsoc_tb_dhrystone_{config_suffix}",
            parameter_overrides={
                "ENABLE_LMEM_EARLY_LOAD_P": int(lmem_early_load_enabled),
                "ENABLE_LOAD_RESPONSE_BYPASS_P": int(load_response_bypass_enabled),
                "ENABLE_BHT_P": int(bht_enabled),
                "ENABLE_RAS_P": int(ras_enabled),
                "ENABLE_UPPER_32_PREFETCH_P": int(upper_32_prefetch_enabled),
            },
            # CVFPU drives pipeline stage 0 combinationally and later stages
            # sequentially.  Verilator reports its non-overlapping packed
            # slices as BLKANDNBLK; use the same vendor compatibility policy
            # as the M2 core and SoC regressions.
            warning_suppresses=("BLKANDNBLK",),
            warnings_fatal=False,
        )
        if not built:
            print(f"DHRY SIM FAIL: {reason}", file=sys.stderr)
            return 1
        passed, reason, elapsed = run_verilator(
            binary,
            [
                "+tc=DHRY-SMOKE",
                f"+instr_mem_file={imem.resolve().as_posix()}",
                f"+data_mem_file={dmem.resolve().as_posix()}",
                f"+boot_addr={elf_entry_point(elf):x}",
                f"+tohost_addr={result_index:x}",
                "+expected_tohost=80000000",
                "+expected_tohost_mask=c0000000",
                *report_args.split(),
                *perf_profile_args,
                f"+max_cycles={args.max_cycles}",
            ],
            log_path,
            PASS_MARKER,
            FAIL_MARKERS,
        )
    if not passed:
        print(f"DHRY SIM FAIL: {reason}", file=sys.stderr)
        return 1

    log_text = log_path.read_text(encoding="utf-8")
    match = re.search(r"TB INFO: tohost reached value=([0-9a-fA-F]+)", log_text)
    if match is None:
        print("DHRY SIM FAIL: missing result word", file=sys.stderr)
        return 1
    result_word = int(match.group(1), 16)
    if (result_word & 0xc0000000) != 0x80000000:
        print(f"DHRY SIM FAIL: result validation failed (result=0x{result_word:08x})", file=sys.stderr)
        return 1

    report = {
        int(index): int(value, 16)
        for index, value in re.findall(
            r"TB REPORT: word\[(\d+)\]=([0-9a-fA-F]+)",
            log_text,
        )
    }
    expected_arr2 = args.iterations + 10
    if args.hpm and report.get(0) != HPM_REPORT_MAGIC:
        print(f"DHRY SIM FAIL: HPM report magic mismatch (actual=0x{report.get(0, 0):08x})", file=sys.stderr)
        return 1
    if args.hpm and report.get(1) != expected_arr2:
        print(
            "DHRY SIM FAIL: Arr_2_Glob[8][7] mismatch "
            f"(expected={expected_arr2} actual={report.get(1)})",
            file=sys.stderr,
        )
        return 1
    mcycle = result_word & 0x3fffffff
    if args.hpm and report.get(2) != mcycle:
        print(
            f"DHRY SIM FAIL: HPM cycle mismatch (result={mcycle} report={report.get(2)})",
            file=sys.stderr,
        )
        return 1
    csv_row = append_dhrystone_csv(
        root=ROOT, csv_path=args.results_csv, product="M2", backend=backend,
        iterations=args.iterations, sw_dir=SW_DIR, elf=elf, imem=imem, dmem=dmem,
        raw_mcycle=mcycle, elapsed_seconds=elapsed, hpm_enabled=args.hpm,
        hpm_report=report, log_path=log_path,
        core_lmem_early_load=lmem_early_load_enabled,
        core_load_response_bypass=load_response_bypass_enabled,
        core_bht=bht_enabled,
        core_ras=ras_enabled,
        core_upper_32_prefetch=upper_32_prefetch_enabled,
        compiler_layout_align=layout_align_enabled,
    )
    message = (
        "DHRY SIM PASS: "
        f"functional validation passed; iterations={args.iterations} raw_mcycle={mcycle} "
        f"cycles_per_iteration={mcycle / args.iterations:.3f} "
        f"dhrystones_per_second_at_1mhz={args.iterations * 1_000_000 / mcycle:.3f} "
        f"dmips_per_mhz={args.iterations * 1_000_000 / mcycle / VAX_11_780_DHRYSTONES_PER_SECOND:.3f} "
        f"lmem_early_load={int(lmem_early_load_enabled)} "
        f"load_response_bypass={int(load_response_bypass_enabled)} "
        f"bht={int(bht_enabled)} ras={int(ras_enabled)} "
        f"upper_32_prefetch={int(upper_32_prefetch_enabled)} "
        f"layout_align={int(layout_align_enabled)} "
    )
    if args.hpm:
        message += (
            f"arr2_8_7={report[1]} instret={report.get(3, 0)} "
            f"branch_taken={report.get(4, 0)} ifetch_wait={report.get(5, 0)} "
            f"data_wait={report.get(6, 0)} load_use_stall={report.get(7, 0)} "
        )
    print(f"{message}wall_s={elapsed:.1f} csv={args.results_csv} "
          f"tb_profile={csv_row['tb_profile_available']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
