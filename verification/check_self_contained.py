#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Reject M2 source and verification references to another MCU product tree."""

from __future__ import annotations

import re
from pathlib import Path


M2_ROOT = Path(__file__).resolve().parents[1]
SCAN_ROOTS = ("rtl", "dv", "sw", "tests", "compliance", "fpga")
FOREIGN_PRODUCT_PATH = re.compile(r"(?:^|[\\/])eriscv-m[01](?:[\\/]|$)")


def main() -> int:
    failures: list[str] = []
    for relative_root in SCAN_ROOTS:
        root = M2_ROOT / relative_root
        if not root.exists():
            continue
        for candidate in root.rglob("*"):
            if not candidate.is_file():
                continue
            for line_number, line in enumerate(
                candidate.read_text(encoding="utf-8", errors="ignore").splitlines(), start=1
            ):
                if FOREIGN_PRODUCT_PATH.search(line):
                    failures.append(f"{candidate.relative_to(M2_ROOT)}:{line_number}: {line.strip()}")

    if failures:
        print("M2 self-containment check failed:")
        print("\n".join(failures))
        return 1

    print("M2 self-containment check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
