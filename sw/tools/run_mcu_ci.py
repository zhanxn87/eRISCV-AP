#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Build and ModelSim-check the eRISCV-M2 BSP suite."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

SW_DIR = Path(__file__).resolve().parents[1]
RUNNER = SW_DIR / "tools" / "run_hello_uart_sim.py"

EXAMPLES = (
    ("hello_uart", "BSP-HELLO-UART", 4_000, "655249534356204d4355204253502068656c6c6f0d0a"),
    ("timer_apb_poll", "BSP-TIMER-APB", 3_000_000, ""),
    ("timer_clint", "BSP-TIMER-CLINT", 800_000, ""),
    ("wfi_tickless", "BSP-WFI-TICKLESS", 800_000, ""),
    ("irq_timer_uart", "BSP-IRQ-TIMER-UART", 1_000_000, ""),
    ("wdt_smoke", "BSP-WDT-SMOKE", 2_000_000, ""),
    ("dma_system_sram", "BSP-DMA-SYSTEM-SRAM", 20_000,
     "6552495343562d4d3220444d4120504153530d0a"),
    ("dma_irq_wfi", "BSP-DMA-IRQ-WFI", 20_000,
     "6552495343562d4d3220444d41204952512057464920504153530d0a"),
    ("dma_descriptor_chain", "BSP-DMA-DESCRIPTOR-CHAIN", 20_000,
     "6552495343562d4d3220444d412064657363726970746f7220504153530d0a"),
    ("dma_descriptor_irq_wfi", "BSP-DMA-DESCRIPTOR-IRQ-WFI", 20_000,
     "6552495343562d4d3220444d412064657363726970746f72204952512057464920504153530d0a"),
    ("fpu_dma_sram", "BSP-FPU-DMA-SRAM", 20_000,
     "6552495343562d4d322046505520444d41205352414d20504153530d0a"),
    ("fpu_fft", "BSP-FPU-FFT128", 120_000,
     "6552495343562d4d32204650552046465431323820504153530d0a"),
)


def run(command: list[str]) -> None:
    print("+", " ".join(command), flush=True)
    subprocess.run(command, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()

    if not args.skip_build:
        for example, _, _, _ in EXAMPLES:
            run(["make", "-C", str(SW_DIR), f"EXAMPLE={example}", "images"])

    for example, testcase, max_cycles, expected_uart in EXAMPLES:
        run([
            sys.executable, str(RUNNER), "--backend", "modelsim",
            "--example", example, "--tc", testcase,
            "--max-cycles", str(max_cycles),
            "--expected-uart", expected_uart,
            "--expected-gpio-out", "1", "--expected-gpio-oe", "1",
        ])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
