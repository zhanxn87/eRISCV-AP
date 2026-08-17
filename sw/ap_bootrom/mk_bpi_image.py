#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause
"""Pack the AP first-stage payload into x16 BPI NOR $readmemh words."""

import argparse
import struct
from pathlib import Path

AP_BOOT_MAGIC = 0x4552495343564150
AP_BOOT_VERSION = 1
AP_HEADER_BYTES = 64
AP_DDR_BASE = 0x0000000080000000
AP_DDR_LIMIT = 0x0000000100000000


def xor64_words(data: bytes) -> int:
    """Return the non-cryptographic 64-bit XOR integrity value for `data`."""
    assert len(data) % 8 == 0
    checksum = 0
    for offset in range(0, len(data), 8):
        checksum ^= int.from_bytes(data[offset:offset + 8], "little")
    return checksum


def parse_int(value: str) -> int:
    return int(value, 0)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--payload-bin", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--load-addr", required=True, type=parse_int)
    parser.add_argument("--entry-addr", required=True, type=parse_int)
    args = parser.parse_args()

    payload = args.payload_bin.read_bytes()
    if not payload:
        raise SystemExit("payload must not be empty")
    payload += bytes((-len(payload)) % 8)
    payload_checksum = xor64_words(payload)

    payload_end = args.load_addr + len(payload)
    if not (AP_DDR_BASE <= args.load_addr < payload_end <= AP_DDR_LIMIT):
        raise SystemExit("payload load range must fit the AP DDR aperture")
    if not (args.load_addr <= args.entry_addr < payload_end):
        raise SystemExit("entry address must reside within the payload")

    header = struct.pack(
        "<8Q",
        AP_BOOT_MAGIC,
        AP_BOOT_VERSION,
        len(payload),
        args.load_addr,
        args.entry_addr,
        payload_checksum,
        0,
        0,
    )
    assert len(header) == AP_HEADER_BYTES
    image = header + payload
    assert len(image) % 2 == 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        "\n".join(
            f"{int.from_bytes(image[offset:offset + 2], 'little'):04x}"
            for offset in range(0, len(image), 2)
        ) + "\n",
        encoding="ascii",
    )


if __name__ == "__main__":
    main()
