#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Build and ModelSim-check the M2 Zephyr multi-thread demo."""

from __future__ import annotations

import argparse
import os
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
RESULT_SYMBOL = "eriscv_zephyr_result"
PASS_RESULT = 0x5A6B7C8D
PASS_MARKER = "ERISCV_M2_SOC PASS:"
FAIL_MARKERS = ("ERISCV_M2_SOC FAIL:", "TB ERROR:", "** Error:", "** Fatal:", "Fatal:")
DEFAULT_ZEPHYR_BASE = str(ROOT / "third_party/zephyr")
DEFAULT_UART_SIM_CONF = SW_DIR / "rtos/zephyr/app/prj_sim.conf"
LOW_POWER_APP_DIR = SW_DIR / "rtos/zephyr/app_low_power"


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
                raise RuntimeError(
                    f"{RESULT_SYMBOL} is not an aligned DTCM address: 0x{address:08x}"
                )
            return (address - DMEM_BASE) >> 2
    raise RuntimeError(f"ELF does not define {RESULT_SYMBOL}")


def uart_divisor(config: Path) -> int:
    match = re.search(
        r"^CONFIG_UART_ERISCV_BAUD_DIVISOR=(\d+)$",
        config.read_text(encoding="utf-8"),
        re.MULTILINE,
    )
    if match is None or int(match.group(1)) <= 0:
        raise RuntimeError(f"invalid UART divisor in {config}")
    return int(match.group(1))


def print_summary(low_power: bool, result_word: int, baud_divisor: int, elapsed: float) -> None:
    rows = [
        ("mode", "tickless WFI/CLINT wake" if low_power else "multi-thread smoke"),
        ("result word", f"PASS (0x{result_word:08x})"),
    ]
    if low_power:
        rows.append(("WFI low-power and CLINT wake", "PASS"))
    else:
        rows.extend((
            ("UART baud configuration", f"PASS (divisor={baud_divisor})"),
            ("mutex and message queue", "PASS (four A-to-B handoffs)"),
            ("SPI loopback", "PASS (MOSI=0xa5, MISO=0x3c)"),
            ("GPIO output / enable", "PASS (out=0x5, oe=0x7)"),
        ))
    rows.append(("ModelSim wall time", f"{elapsed:.1f} s"))
    width = max(len(name) for name, _ in rows)
    print("ZEPHYR SUMMARY: PASS")
    print(f"  {'Check':<{width}}  Result")
    print(f"  {'-' * width}  ------")
    for name, value in rows:
        print(f"  {name:<{width}}  {value}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--max-cycles", type=int, default=2_000_000)
    parser.add_argument("--vsim", default=default_vsim())
    parser.add_argument("--zephyr-base", default=os.environ.get("ZEPHYR_BASE", DEFAULT_ZEPHYR_BASE))
    parser.add_argument("--uart-config", type=Path, default=DEFAULT_UART_SIM_CONF)
    parser.add_argument("--low-power", action="store_true",
                        help="run the dedicated tickless WFI/CLINT wake smoke")
    args = parser.parse_args()
    if args.max_cycles <= 0:
        parser.error("max-cycles must be positive")
    config = LOW_POWER_APP_DIR / "prj.conf" if args.low_power else args.uart_config
    if not config.is_file():
        parser.error(f"Zephyr config not found: {config}")
    if not args.low_power:
        try:
            baud_divisor = uart_divisor(config)
        except RuntimeError as error:
            parser.error(str(error))
    else:
        baud_divisor = 0

    app_dir = LOW_POWER_APP_DIR if args.low_power else SW_DIR / "rtos/zephyr/app"
    build_dir = SW_DIR / ("build/zephyr_low_power" if args.low_power else "build/zephyr")

    # Build Zephyr
    env = os.environ.copy()
    env.setdefault("ZEPHYR_BASE", args.zephyr_base)
    subprocess.run(
        [
            "make", "-B", "-C", str(SW_DIR / "rtos/zephyr"),
            f"APP_DIR={app_dir.resolve()}",
            f"BUILD_DIR={build_dir.resolve()}",
            f"EXTRA_CONF_FILE={config.resolve()}", "images",
        ],
        env=env,
        check=True,
    )
    elf = build_dir / "zephyr/zephyr.elf"
    imem = build_dir / "zephyr.imem.mem"
    dmem = build_dir / "zephyr.dmem.mem"
    if not elf.exists():
        print("ZEPHYR BUILD FAIL: ELF not found", file=sys.stderr)
        return 1

    result_index = result_word_index(elf)
    log_path = build_dir / "zephyr.sim.log"

    write_resolved_filelist(SIM_DIR / "filelist.f", SIM_DIR / "file.list")
    command = (
        "if {![file exists work]} { vlib work }; "
        "vmap work work; "
        "vlog +acc -work work -incr -f file.list; "
        f"vsim -lib work -t 1ps +tc={'ZEPHYR-LOW-POWER' if args.low_power else 'ZEPHYR-SMOKE'} "
        f"+instr_mem_file={path_for_vsim(args.vsim, imem)} "
        f"+data_mem_file={path_for_vsim(args.vsim, dmem)} "
        f"+boot_addr={elf_entry_point(elf):x} "
        f"+tohost_addr={result_index:x} "
        f"+expected_tohost={PASS_RESULT:x} "
        f"+max_cycles={args.max_cycles} soc_tb; run -all; quit -f"
    )
    if args.low_power:
        command = command.replace(" +max_cycles", " +expect_low_power +max_cycles")
    else:
        command = command.replace(
            " +max_cycles",
            f" +uart_baud_div={baud_divisor} +expected_uart_baud_div={baud_divisor} "
            "+spi_miso_byte=3c +expected_spi_tx=a5 +expected_gpio_out=5 "
            "+expected_gpio_oe=7 +max_cycles",
        )
    passed, reason, elapsed = run_modelsim(
        SIM_DIR, args.vsim, command, log_path, PASS_MARKER, FAIL_MARKERS
    )
    if not passed:
        print(f"ZEPHYR SIM FAIL: {reason}", file=sys.stderr)
        return 1

    match = re.search(
        r"TB INFO: tohost reached value=([0-9a-fA-F]+)",
        log_path.read_text(encoding="utf-8"),
    )
    if match is None:
        print("ZEPHYR SIM FAIL: missing result word", file=sys.stderr)
        return 1
    result_word = int(match.group(1), 16)
    if result_word != PASS_RESULT:
        print(
            f"ZEPHYR SIM FAIL: unexpected result 0x{result_word:08x} "
            f"(expected 0x{PASS_RESULT:08x})",
            file=sys.stderr,
        )
        return 1

    print_summary(args.low_power, result_word, baud_divisor, elapsed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
