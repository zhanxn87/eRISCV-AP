/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

OUTPUT_ARCH("riscv")
ENTRY(rvtest_entry_point)

SECTIONS
{
  . = 0x00000000;
  .text.trap : { *(.text.trap) }

  . = 0x00000080;
  .text.init : { *(.text.init) }
  .text.rvtest : { *(.text.rvtest) *(.text.rvtest.*) }

  . = ALIGN(0x1000);
  .text.rvmodel : { *(.text.rvmodel) *(.text.rvmodel.*) *(.text) *(.text.*) }
  _etext = .;

  /* Keep folded SRAM word indices distinct in the educational TB. */
  . = 0x00040000;
  .tohost : { *(.tohost) }

  . = 0x00040200;
  .data : { *(.data) }
  .data.string : { *(.data.string) }
  .bss : { *(.bss) }
  _end = .;
}
