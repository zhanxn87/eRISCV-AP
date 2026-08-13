#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Build and run an eRISCV-M2 BSP UART smoke, preferring Verilator."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
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

PASS_MARKER = "ERISCV_M2_SOC PASS:"
FAIL_MARKERS = ("ERISCV_M2_SOC FAIL:", "TB ERROR:", "** Error:", "** Fatal:", "Fatal:")
DEFAULT_HELLO_BYTES = "655249534356204d4355204253502068656c6c6f0d0a"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--example", default="hello_uart")
    parser.add_argument("--tc", default="BSP-HELLO-UART")
    parser.add_argument("--expected-uart", default=DEFAULT_HELLO_BYTES)
    parser.add_argument("--backend", choices=("auto", "modelsim", "verilator"), default="auto")
    parser.add_argument("--vsim", default=default_vsim())
    parser.add_argument("--verilator", default="verilator")
    parser.add_argument("--max-cycles", type=int, default=4000)
    parser.add_argument("--expected-gpio-out", default="1")
    parser.add_argument("--expected-gpio-oe", default="1")
    args = parser.parse_args()

    build_dir = ROOT / "eriscv-m2/sw/build" / args.example
    subprocess.run(
        ["make", "-C", str(ROOT / "eriscv-m2/sw"), f"EXAMPLE={args.example}", "images"],
        check=True,
    )
    write_resolved_filelist(SIM_DIR / "filelist.f", SIM_DIR / "file.list")
    imem = build_dir / f"{args.example}.imem.mem"
    dmem = build_dir / f"{args.example}.dmem.mem"
    boot_addr = elf_entry_point(build_dir / f"{args.example}.elf")
    log_path = build_dir / f"{args.example}.sim.log"
    backend = select_backend(args.backend, args.vsim, args.verilator)

    if backend == "modelsim":
        command = (
            "if {![file exists work]} { vlib work }; "
            "vmap work work; "
            "vlog +acc -work work -incr -f file.list; "
            f"vsim -lib work -t 1ps +tc={args.tc} "
            f"+instr_mem_file={path_for_vsim(args.vsim, imem)} "
            f"+data_mem_file={path_for_vsim(args.vsim, dmem)} "
            f"+boot_addr={boot_addr:x} "
            f"+max_cycles={args.max_cycles} "
            "+expected_uart_tx_bytes=" + args.expected_uart + " "
            "+uart_baud_div=8 "
            "+expected_gpio_out=" + args.expected_gpio_out + " "
            "+expected_gpio_oe=" + args.expected_gpio_oe + " "
            "soc_tb; run -all; quit -f"
        )
        passed, reason, _ = run_modelsim(
            SIM_DIR, args.vsim, command, log_path, PASS_MARKER, FAIL_MARKERS
        )
    else:
        built, reason, binary = build_verilator(
            SIM_DIR,
            build_dir,
            args.verilator,
            "soc_tb",
            binary_name="Vsoc_tb_bsp",
        )
        if not built:
            print(f"BSP SIM FAIL: {reason}", file=sys.stderr)
            return 1
        passed, reason, _ = run_verilator(
            binary,
            [
                f"+tc={args.tc}",
                f"+instr_mem_file={imem.resolve().as_posix()}",
                f"+data_mem_file={dmem.resolve().as_posix()}",
                f"+boot_addr={boot_addr:x}",
                f"+max_cycles={args.max_cycles}",
                "+expected_uart_tx_bytes=" + args.expected_uart,
                "+uart_baud_div=8",
                "+expected_gpio_out=" + args.expected_gpio_out,
                "+expected_gpio_oe=" + args.expected_gpio_oe,
            ],
            log_path,
            PASS_MARKER,
            FAIL_MARKERS,
        )
    print(f"BSP SIM {'PASS' if passed else 'FAIL'}: {reason}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
