#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Build and simulator-check the M2 CoreMark measurement."""

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

from resolve_filelist import write_resolved_filelist
from elf_to_mem import elf_entry_point
from sim_backend import (
    build_verilator,
    default_vsim,
    path_for_vsim,
    run_modelsim,
    run_verilator,
    select_backend,
)

DMEM_BASE = 0x11000000
RESULT_SYMBOL = "eriscv_coremark_result"
PASS_MARKER = "ERISCV_M2_SOC PASS:"
FAIL_MARKERS = ("ERISCV_M2_SOC FAIL:", "TB ERROR:", "** Error:", "** Fatal:", "Fatal:")


def result_word_index(elf: Path) -> int:
    result = subprocess.run(
        ["riscv64-unknown-elf-nm", "-n", str(elf)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=True,
    )
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[2] == RESULT_SYMBOL:
            address = int(fields[0], 16)
            if address < DMEM_BASE or (address & 3) != 0:
                raise RuntimeError(f"{RESULT_SYMBOL} is not an aligned DTCM address: 0x{address:08x}")
            return (address - DMEM_BASE) >> 2
    raise RuntimeError(f"ELF does not define {RESULT_SYMBOL}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iterations", type=int, default=1)
    parser.add_argument("--max-cycles", type=int, default=400_000_000)
    parser.add_argument("--backend", choices=("auto", "modelsim", "verilator"), default="auto")
    parser.add_argument("--vsim", default=default_vsim())
    parser.add_argument("--verilator", default="verilator")
    parser.add_argument("--mul-iter-bits", type=int, choices=(8, 16), default=16,
                        help="RV32M multiplier bits consumed per iterative compute cycle")
    args = parser.parse_args()
    if args.iterations <= 0 or args.max_cycles <= 0:
        parser.error("iterations and max-cycles must be positive")

    subprocess.run(
        ["make", "-B", "-C", str(SW_DIR), "coremark", f"COREMARK_ITERATIONS={args.iterations}"],
        check=True,
    )
    build_dir = SW_DIR / "build/coremark"
    elf = build_dir / "coremark.elf"
    imem = build_dir / "coremark.imem.mem"
    dmem = build_dir / "coremark.dmem.mem"
    boot_addr = elf_entry_point(elf)
    result_index = result_word_index(elf)
    config_suffix = f"all_enabled.mul{args.mul_iter_bits}"
    log_path = build_dir / f"coremark.{config_suffix}.sim.log"

    write_resolved_filelist(SIM_DIR / "filelist.f", SIM_DIR / "file.list")
    backend = select_backend(args.backend, args.vsim, args.verilator)
    parameter_overrides = {
        "ENABLE_LMEM_EARLY_LOAD_P": 1,
        "ENABLE_LOAD_RESPONSE_BYPASS_P": 1,
        "ENABLE_BHT_P": 1,
        "ENABLE_RAS_P": 1,
        "ENABLE_UPPER_32_PREFETCH_P": 1,
        "MUL_ITER_BITS_P": args.mul_iter_bits,
    }
    plusargs = [
        "+tc=COREMARK-SMOKE",
        f"+instr_mem_file={imem.resolve().as_posix()}",
        f"+data_mem_file={dmem.resolve().as_posix()}",
        f"+boot_addr={boot_addr:x}",
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
            "vsim -lib work -t 1ps "
            "-gENABLE_LMEM_EARLY_LOAD_P=1 "
            "-gENABLE_LOAD_RESPONSE_BYPASS_P=1 "
            "-gENABLE_BHT_P=1 -gENABLE_RAS_P=1 "
            "-gENABLE_UPPER_32_PREFETCH_P=1 "
            f"-gMUL_ITER_BITS_P={args.mul_iter_bits} "
            "+tc=COREMARK-SMOKE "
            f"+instr_mem_file={path_for_vsim(args.vsim, imem)} "
            f"+data_mem_file={path_for_vsim(args.vsim, dmem)} "
            f"+boot_addr={boot_addr:x} +tohost_addr={result_index:x} "
            "+expected_tohost=80000000 +expected_tohost_mask=c0000000 "
            f"+max_cycles={args.max_cycles} soc_tb; run -all; quit -f"
        )
        passed, reason, elapsed = run_modelsim(
            SIM_DIR, args.vsim, command, log_path, PASS_MARKER, FAIL_MARKERS
        )
    else:
        built, reason, binary = build_verilator(
            SIM_DIR, build_dir, args.verilator, "soc_tb",
            binary_name=f"Vsoc_tb_coremark_{config_suffix}",
            parameter_overrides=parameter_overrides,
            warning_suppresses=("BLKANDNBLK",),
            warnings_fatal=False,
        )
        if not built:
            print(f"COREMARK SIM FAIL: {reason}", file=sys.stderr)
            return 1
        passed, reason, elapsed = run_verilator(
            binary, plusargs, log_path, PASS_MARKER, FAIL_MARKERS
        )
    if not passed:
        print(f"COREMARK SIM FAIL: {reason}", file=sys.stderr)
        return 1

    match = re.search(r"TB INFO: tohost reached value=([0-9a-fA-F]+)", log_path.read_text(encoding="utf-8"))
    if match is None:
        print("COREMARK SIM FAIL: missing result word", file=sys.stderr)
        return 1
    result_word = int(match.group(1), 16)
    if (result_word & 0xc0000000) != 0x80000000:
        print(f"COREMARK SIM FAIL: CRC validation failed (result=0x{result_word:08x})", file=sys.stderr)
        return 1
    mcycle = result_word & 0x3fffffff
    print(
        "COREMARK SIM PASS: "
        f"backend={backend} iterations={args.iterations} mul_iter_bits={args.mul_iter_bits} mcycle={mcycle} "
        f"cycles_per_iteration={mcycle / args.iterations:.3f} "
        f"coremark_per_mhz={args.iterations * 1_000_000 / mcycle:.6f} "
        f"wall_s={elapsed:.1f}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
