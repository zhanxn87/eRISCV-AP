#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

"""Resolve nested HDL file lists into one simulator-ready file list.

Supported source-list entries are SystemVerilog files, ``+incdir+`` directives,
``+define+`` directives, other simulator options, and ``-f <filelist>`` includes.
Every relative path is resolved against the file list that contains it.
"""

from __future__ import annotations

import argparse
import os
import re
from dataclasses import dataclass
from pathlib import Path


class FileListError(RuntimeError):
    """A nested source-list reference could not be resolved safely."""


@dataclass(frozen=True)
class FileListEntry:
    kind: str
    value: Path | str


LITERAL_INCLUDE_RE = re.compile(r'^\s*`include\s+"([^"]+)"')


def _source_error(source: Path, line_number: int, message: str) -> FileListError:
    return FileListError(f"{source}:{line_number}: {message}")


def _resolve_path(source: Path, line_number: int, value: str) -> Path:
    path = (source.parent / value).resolve()
    if not path.exists():
        raise _source_error(source, line_number, f"referenced path does not exist: {value}")
    return path


def _iter_lines(filelist: Path) -> list[tuple[int, str]]:
    lines: list[tuple[int, str]] = []
    pending = ""
    pending_line = 0
    for line_number, raw_line in enumerate(filelist.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("//") or line.startswith("#"):
            continue
        if pending:
            line = pending + line
        if line.endswith("\\"):
            pending = line[:-1].rstrip() + " "
            if not pending_line:
                pending_line = line_number
            continue
        lines.append((pending_line or line_number, line))
        pending = ""
        pending_line = 0
    if pending:
        raise _source_error(filelist, pending_line, "unterminated line continuation")
    return lines


def _source_local_include_dirs(entries: list[FileListEntry]) -> list[Path]:
    """Find source-local directories needed by literal `include directives."""

    include_dirs: list[Path] = []
    for entry in entries:
        if entry.kind != "source":
            continue
        source = entry.value
        assert isinstance(source, Path)
        for line in source.read_text(encoding="utf-8").splitlines():
            match = LITERAL_INCLUDE_RE.match(line)
            if match and (source.parent / match.group(1)).is_file():
                include_dirs.append(source.parent)
                break
    return include_dirs


def resolve_filelist(filelist: Path) -> list[FileListEntry]:
    """Return ordered, de-duplicated entries from a recursively nested list."""
    filelist = Path(filelist)

    entries: list[FileListEntry] = []
    seen_sources: set[Path] = set()
    seen_include_dirs: set[Path] = set()
    seen_options: set[str] = set()
    active_lists: list[Path] = []

    def visit(source: Path) -> None:
        source = source.resolve()
        if source in active_lists:
            cycle = " -> ".join(path.as_posix() for path in [*active_lists, source])
            raise FileListError(f"nested file-list cycle: {cycle}")
        active_lists.append(source)
        try:
            for line_number, line in _iter_lines(source):
                if line == "-f" or line.startswith("-f "):
                    nested = line[2:].strip()
                    if not nested:
                        raise _source_error(source, line_number, "-f requires a file-list path")
                    visit(_resolve_path(source, line_number, nested))
                    continue

                if line.startswith("+incdir+"):
                    directories = [item for item in line.removeprefix("+incdir+").split("+") if item]
                    if not directories:
                        raise _source_error(source, line_number, "+incdir+ requires a directory")
                    for directory in directories:
                        path = _resolve_path(source, line_number, directory)
                        if not path.is_dir():
                            raise _source_error(source, line_number, f"include path is not a directory: {directory}")
                        if path not in seen_include_dirs:
                            seen_include_dirs.add(path)
                            entries.append(FileListEntry("incdir", path))
                    continue

                if line.startswith("+") or line.startswith("-"):
                    if line not in seen_options:
                        seen_options.add(line)
                        entries.append(FileListEntry("option", line))
                    continue

                path = _resolve_path(source, line_number, line)
                if path.is_dir():
                    raise _source_error(source, line_number, f"source entry is a directory: {line}")
                if path not in seen_sources:
                    seen_sources.add(path)
                    entries.append(FileListEntry("source", path))
        finally:
            active_lists.pop()

    visit(filelist)

    existing_include_dirs = {entry.value for entry in entries if entry.kind == "incdir"}
    implicit_include_dirs = [
        directory
        for directory in _source_local_include_dirs(entries)
        if directory not in existing_include_dirs
    ]
    if implicit_include_dirs:
        first_non_include = next(
            (index for index, entry in enumerate(entries) if entry.kind != "incdir"),
            len(entries),
        )
        entries[first_non_include:first_non_include] = [
            FileListEntry("incdir", directory) for directory in dict.fromkeys(implicit_include_dirs)
        ]
    return entries


def render_filelist(entries: list[FileListEntry], output: Path, absolute: bool = False) -> str:
    output_dir = output.resolve().parent

    def render_path(path: Path) -> str:
        if absolute:
            return path.as_posix()
        return os.path.relpath(path, output_dir).replace(os.sep, "/")

    lines = [
        "// Generated by tools/project/resolve_filelist.py. Do not edit.",
        "// Edit the source filelist.f hierarchy instead.",
        "",
    ]
    for entry in entries:
        if entry.kind == "incdir":
            lines.append(f"+incdir+{render_path(entry.value)}")
        elif entry.kind == "source":
            lines.append(render_path(entry.value))
        else:
            lines.append(str(entry.value))
    return "\n".join(lines) + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("filelist", type=Path, help="Top-level nested filelist.f")
    parser.add_argument("--output", type=Path, help="Generated flattened file-list path")
    parser.add_argument("--check", action="store_true", help="Validate without writing")
    parser.add_argument("--absolute", action="store_true", help="Emit absolute source paths")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.check and args.output is None:
        raise SystemExit("--output is required unless --check is used")
    try:
        entries = resolve_filelist(args.filelist)
    except FileListError as exc:
        print(f"filelist error: {exc}")
        return 2
    if args.check:
        source_count = sum(entry.kind == "source" for entry in entries)
        include_count = sum(entry.kind == "incdir" for entry in entries)
        print(f"filelist OK: {source_count} sources, {include_count} include directories")
        return 0
    assert args.output is not None
    rendered = render_filelist(entries, args.output, absolute=args.absolute)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if not args.output.exists() or args.output.read_text(encoding="utf-8") != rendered:
        args.output.write_text(rendered, encoding="utf-8")
        action = "generated"
    else:
        action = "unchanged"
    print(f"{action} {args.output}: {sum(entry.kind == 'source' for entry in entries)} sources")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
