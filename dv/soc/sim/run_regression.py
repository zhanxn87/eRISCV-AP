#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""eRISCV-M2 SoC regression runner."""

from __future__ import annotations

import sys
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parents[4] / "tools"
sys.path.insert(0, str(TOOLS_DIR / "sim"))
sys.path.insert(0, str(TOOLS_DIR / "project"))
from phase_regression import DEFAULT_FAIL_MARKERS, PhaseRegressionConfig, run_phase_regression
from resolve_filelist import write_resolved_filelist

PASS_MARKER = "ERISCV_M2_SOC PASS:"
FAIL_MARKERS = ("ERISCV_M2_SOC FAIL:", *DEFAULT_FAIL_MARKERS)
BOOT_ADDR = 0x10000000

SOC_TESTS = {
    # ISA/product contract
    "MCU-C-01":           {"phase": "core/C", "max_cycles": 900, "boot_addr": BOOT_ADDR},
    "MCU-C-LS-01":        {"phase": "core/C", "max_cycles": 260, "boot_addr": BOOT_ADDR},
    "MCU-C-SP-01":        {"phase": "core/C", "max_cycles": 260, "boot_addr": BOOT_ADDR},
    "MCU-C-MIXED-PC-01":  {"phase": "core/C", "max_cycles": 260, "boot_addr": BOOT_ADDR},
    "MCU-C-IRQ-MEPC-01":  {"phase": "core/C", "max_cycles": 320, "boot_addr": BOOT_ADDR},
    "MCU-C-DPC-01":       {"phase": "core/C", "max_cycles": 260, "boot_addr": BOOT_ADDR},
    "MCU-C-DEBUG-STEP-SWEEP-01": {"phase": "core/C", "max_cycles": 360, "boot_addr": BOOT_ADDR},
    "MCU-ZIFENCEI-01":    {"phase": "core/Zifencei", "max_cycles": 300, "boot_addr": BOOT_ADDR},
    "MCU-ZIFENCEI-SELF-MODIFY-01": {"phase": "core/Zifencei", "max_cycles": 180, "boot_addr": BOOT_ADDR},
    "MCU-ZIHINTPAUSE-01": {"phase": "core/Zihintpause", "max_cycles": 100, "boot_addr": BOOT_ADDR},
    "MCU-BUS-UNMAPPED-01": {
        "phase": "soc", "max_cycles": 160, "boot_addr": BOOT_ADDR,
        "expected_bus_errors": 1,
    },
    "MCU-STORE-FAST-01": {"phase": "soc", "max_cycles": 220, "boot_addr": BOOT_ADDR},
    "MCU-LMEM-LOAD-BRANCH-01": {
        "phase": "soc", "max_cycles": 220, "boot_addr": BOOT_ADDR,
    },
    "MCU-LMEM-LOAD-STORE-DATA-01": {
        "phase": "soc", "max_cycles": 360, "boot_addr": BOOT_ADDR,
    },
    "MCU-LOAD-RESPONSE-BYPASS-01": {
        "phase": "soc", "max_cycles": 420, "boot_addr": BOOT_ADDR,
    },
    "MCU-TCM-UPPER-HALF-01": {
        "phase": "soc", "max_cycles": 260, "boot_addr": 0x10010000,
    },
    "MCU-CLKRST-01":      {"phase": "soc", "max_cycles": 500, "boot_addr": BOOT_ADDR},
    "MCU-LP-WFI-TIMER-01": {"phase": "soc", "max_cycles": 700, "boot_addr": BOOT_ADDR},
    # Legacy peripheral smoke tests migrated through modular SoC TB agents
    "UART-LOOPBACK-01": {
        "phase": "soc",
        "max_cycles": 700,
        "boot_addr": BOOT_ADDR,
        "expected_uart_tx": "55",
        "uart_rx_byte": "a5",
        "uart_baud_div": 8,
        "uart_rx_start_cycle": 30,
    },
    "UART-HELLO-01": {
        "phase": "soc",
        "max_cycles": 2200,
        "boot_addr": BOOT_ADDR,
        "expected_uart_tx_bytes": "48656c6c6f20576f726c64",
        "uart_baud_div": 8,
    },
    "UART-ECHO-01": {
        "phase": "soc",
        "max_cycles": 700,
        "boot_addr": BOOT_ADDR,
        "expected_uart_tx": "a5",
        "uart_rx_byte": "a5",
        "uart_baud_div": 8,
        "uart_rx_start_cycle": 30,
    },
    "GPIO-BASIC-01": {"phase": "soc", "max_cycles": 160, "boot_addr": BOOT_ADDR, "gpio_in": "a5"},
    "SPI-BASIC-01": {
        "phase": "soc",
        "max_cycles": 260,
        "boot_addr": BOOT_ADDR,
        "spi_miso_byte": "3c",
        "expected_spi_tx": "a5",
    },
    "TIMER-POLL-01": {
        "phase": "soc",
        "max_cycles": 400,
        "boot_addr": BOOT_ADDR,
        "boot_mode": "uart_boot",
    },
    "MCU-BOOT-DATA-INIT-01": {
        "phase": "soc", "max_cycles": 1200, "boot_addr": BOOT_ADDR,
        "boot_mode": "uart_boot",
    },
    "MCU-BOOT-DATA-INIT-JTAG-01": {
        "phase": "soc", "image": "MCU-BOOT-DATA-INIT-01", "max_cycles": 1200,
        "boot_addr": BOOT_ADDR, "boot_mode": "jtag_boot",
    },
    "MCU-BOOT-DATA-INIT-JTAG-ELF-01": {
        "phase": "soc", "image": "MCU-BOOT-DATA-INIT-01", "max_cycles": 1200,
        "boot_addr": BOOT_ADDR, "boot_mode": "jtag_boot",
        "jtag_boot_elf": "MCU-BOOT-DATA-INIT-01",
    },
    # CLINT (MSIP/MTIP) register and trap verification
    "MCU-CLINT-01":       {"phase": "soc", "max_cycles": 200, "boot_addr": BOOT_ADDR, "expected_bus_errors": 0},
    "MCU-TIME-CSR-01":    {"phase": "soc", "max_cycles": 400, "boot_addr": BOOT_ADDR},
    "MCU-CLINT-MSIP-IRQ-01": {"phase": "soc", "max_cycles": 300, "boot_addr": BOOT_ADDR},
    "MCU-CLINT-MTIP-IRQ-01": {"phase": "soc", "max_cycles": 400, "boot_addr": BOOT_ADDR},
    # PLIC register + interrupt flow
    "MCU-PLIC-01":        {"phase": "soc", "max_cycles": 500, "boot_addr": BOOT_ADDR},
    "MCU-PLIC-IRQ-01":    {
        "phase": "soc",
        "max_cycles": 800,
        "boot_addr": BOOT_ADDR,
        "plic_src_cycle": 40,
        "plic_src_id": 17,
        "plic_src_duration": 80,
    },
    "MCU-PLIC-SOURCE-SWEEP-01": {"phase": "soc", "max_cycles": 2400, "boot_addr": BOOT_ADDR},
    "MCU-PLIC-PENDING-PRIORITY-01": {"phase": "soc", "max_cycles": 500, "boot_addr": BOOT_ADDR},
    "MCU-DEBUG-ABSTRACT-01": {"phase": "soc", "max_cycles": 120, "boot_addr": BOOT_ADDR},
    "MCU-DEBUG-GPR-SWEEP-01": {"phase": "soc", "max_cycles": 180, "boot_addr": BOOT_ADDR},
    "MCU-DEBUG-COMPLETE-01": {"phase": "soc", "max_cycles": 180, "boot_addr": BOOT_ADDR},
    "MCU-DEBUG-JTAG-01": {"phase": "soc", "max_cycles": 260, "boot_addr": BOOT_ADDR},
    "MCU-DEBUG-JTAG-STRESS-01": {"phase": "soc", "max_cycles": 600, "boot_addr": BOOT_ADDR},
    "MCU-DEBUG-OPENOCD-LIKE-01": {"phase": "soc", "max_cycles": 700, "boot_addr": BOOT_ADDR},
    "MCU-DEBUG-TRIGGER-SBA-01": {
        "phase": "soc", "image": "MCU-DEBUG-ABSTRACT-01", "max_cycles": 180,
        "boot_addr": BOOT_ADDR,
    },
}


CONFIG = PhaseRegressionConfig(
    script_file=__file__,
    phase_label="eRISCV-M2 SoC",
    pass_marker=PASS_MARKER,
    fail_markers=FAIL_MARKERS,
    inherited_tests=SOC_TESTS,
    compliance_phase="soc",
    allow_act=False,
    top_module="soc_tb",
    default_boot_addr=BOOT_ADDR,
    supports_latency_parameters=False,
    supports_addr_width_parameters=False,
    imem_word_addr_width=15,
    dmem_word_addr_width=15,
    act_imem_word_addr_width=15,
    act_dmem_word_addr_width=15,
    # CVFPU drives stage 0 combinationally and later stages sequentially.
    # Verilator flags the non-overlapping packed slices as BLKANDNBLK; retain
    # the vendor RTL and suppress that tool limitation for M2 SoC builds.
    verilator_warning_suppresses=("BLKANDNBLK",),
    # Keep remaining CVFPU/PULP compatibility warnings in the build log.
    verilator_warnings_fatal=False,
    testcase_root_override=str(Path(__file__).resolve().parents[4] / "eriscv-m2"),
    product_dv_layout=True,
)

if __name__ == "__main__":
    sim_dir = Path(__file__).resolve().parent
    write_resolved_filelist(sim_dir / "filelist.f", sim_dir / "file.list")
    raise SystemExit(run_phase_regression(CONFIG))
