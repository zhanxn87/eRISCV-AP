/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  IMEM        (rx) : ORIGIN = 0x10000000, LENGTH = 128K
  DMEM        (rw) : ORIGIN = 0x11000000, LENGTH = 128K
  SYSTEM_SRAM (rw) : ORIGIN = 0x80000000, LENGTH = 512K
}

SECTIONS {
  __eriscv_mcu_boot_addr  = ORIGIN(IMEM);
  __eriscv_mcu_imem_base  = ORIGIN(IMEM);
  __eriscv_mcu_imem_limit = ORIGIN(IMEM) + LENGTH(IMEM);
  __eriscv_mcu_dmem_base  = ORIGIN(DMEM);
  __eriscv_mcu_dmem_limit = ORIGIN(DMEM) + LENGTH(DMEM);
  __eriscv_mcu_system_sram_base  = ORIGIN(SYSTEM_SRAM);
  __eriscv_mcu_system_sram_limit = ORIGIN(SYSTEM_SRAM) + LENGTH(SYSTEM_SRAM);

  .text : {
    KEEP(*(.init))
    *(.text .text.*)
  } > IMEM

  .data : ALIGN(4) {
    __data_start = .;
    *(.data .data.*)
    *(.sdata .sdata.*)
    /* Runtime constants use the independent single-port DTCM. Their load
       image remains in IMEM and is copied by the existing crt0 loop. */
    *(.rodata .rodata.*)
    *(.srodata .srodata.*)
    __data_end = .;
  } > DMEM AT > IMEM
  __data_load_start = LOADADDR(.data);

  .bss (NOLOAD) : ALIGN(4) {
    __bss_start = .;
    *(.sbss .sbss.*)
    *(.bss .bss.*)
    *(COMMON)
    __bss_end = .;
  } > DMEM

  .noinit (NOLOAD) : ALIGN(4) {
    *(.noinit .noinit.*)
  } > DMEM

  .system_sram (NOLOAD) : ALIGN(4) {
    __system_sram_start = .;
    *(.system_sram .system_sram.*)
    __system_sram_end = .;
  } > SYSTEM_SRAM

  __stack_top = __eriscv_mcu_dmem_limit;
  __global_pointer$ = __data_start + 0x800;

  /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.eh_frame*) }
}
