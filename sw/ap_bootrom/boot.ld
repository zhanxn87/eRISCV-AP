/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  . = 0x0000000000000080;
  .text : {
    KEEP(*(.text.init))
    *(.text .text.*)
  }
  /DISCARD/ : { *(.comment .note .eh_frame) }
}
