#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Emit eRISCV-M2 IMEM and DMEM $readmemh images from an ELF32 little-endian file."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

PT_LOAD = 1
PF_W = 2
IMEM_BASE = 0x10000000
IMEM_LIMIT = 0x10020000
DMEM_BASE = 0x11000000
DMEM_LIMIT = 0x11020000


def read_elf32_le(path: Path) -> bytes:
    data = path.read_bytes()
    if data[:4] != b"\x7fELF" or data[4] != 1 or data[5] != 1:
        raise ValueError(f"{path} is not an ELF32 little-endian image")
    return data


def elf_entry_point(path: Path) -> int:
    return struct.unpack_from("<I", read_elf32_le(path), 24)[0]


def load_segments(path: Path) -> list[tuple[int, int, int, bytes]]:
    data = read_elf32_le(path)
    phoff = struct.unpack_from("<I", data, 28)[0]
    phentsize = struct.unpack_from("<H", data, 42)[0]
    phnum = struct.unpack_from("<H", data, 44)[0]
    segments = []
    for index in range(phnum):
        offset = phoff + index * phentsize
        p_type, p_offset, p_vaddr, p_paddr, p_filesz, _, p_flags, _ = struct.unpack_from(
            "<IIIIIIII", data, offset
        )
        if p_type == PT_LOAD and p_filesz:
            segments.append((p_vaddr, p_paddr, p_flags, data[p_offset : p_offset + p_filesz]))
    return segments


def add_bytes(words: dict[int, int], byte_addr: int, payload: bytes, base: int, limit: int) -> None:
    for offset, value in enumerate(payload):
        address = byte_addr + offset
        if not base <= address < limit:
            raise ValueError(f"load byte 0x{address:08x} lies outside image region")
        index = (address - base) >> 2
        lane = (address - base) & 3
        words[index] = (words.get(index, 0) & ~(0xff << (lane * 8))) | (value << (lane * 8))


def write_image(path: Path, words: dict[int, int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", newline="\n") as stream:
        previous = None
        for index in sorted(words):
            if previous is None or index != previous + 1:
                stream.write(f"@{index:x}\n")
            stream.write(f"{words[index]:08x}\n")
            previous = index


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("elf", type=Path)
    parser.add_argument("--imem-out", required=True, type=Path)
    parser.add_argument("--dmem-out", required=True, type=Path)
    args = parser.parse_args()

    imem: dict[int, int] = {}
    dmem: dict[int, int] = {}
    for vaddr, paddr, flags, payload in load_segments(args.elf):
        for offset, value in enumerate(payload):
            physical_addr = paddr + offset
            virtual_addr = vaddr + offset
            if IMEM_BASE <= physical_addr < IMEM_LIMIT:
                add_bytes(imem, physical_addr, bytes([value]), IMEM_BASE, IMEM_LIMIT)
            if DMEM_BASE <= virtual_addr < DMEM_LIMIT:
                add_bytes(dmem, virtual_addr, bytes([value]), DMEM_BASE, DMEM_LIMIT)

    if not imem:
        raise ValueError("ELF has no IMEM loadable bytes")
    write_image(args.imem_out, imem)
    write_image(args.dmem_out, dmem)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
