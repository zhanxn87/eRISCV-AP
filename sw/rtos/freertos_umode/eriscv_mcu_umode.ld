/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  IMEM        (rx)  : ORIGIN = 0x10000000, LENGTH = 128K
  USER0_DMEM  (rw)  : ORIGIN = 0x11000000, LENGTH = 4K
  USER1_DMEM  (rw)  : ORIGIN = 0x11001000, LENGTH = 4K
  USER2_DMEM  (rw)  : ORIGIN = 0x11002000, LENGTH = 4K
  USER3_DMEM  (rw)  : ORIGIN = 0x11003000, LENGTH = 4K
  KERNEL_DMEM (rw)  : ORIGIN = 0x11004000, LENGTH = 112K
}

SECTIONS {
  __eriscv_mcu_boot_addr = ORIGIN(IMEM);
  __eriscv_mcu_imem_base = ORIGIN(IMEM);
  __eriscv_mcu_imem_limit = ORIGIN(IMEM) + LENGTH(IMEM);
  __eriscv_mcu_dmem_base = ORIGIN(USER0_DMEM);
  __eriscv_mcu_dmem_limit = ORIGIN(KERNEL_DMEM) + LENGTH(KERNEL_DMEM);

  .text : {
    KEEP(*(.init))
    *(.text .text.*)
    *(.rodata .rodata.*)
  } > IMEM

  .data : ALIGN(4) {
    __data_start = .;
    *(.data .data.*)
    *(.sdata .sdata.*)
    __data_end = .;
  } > KERNEL_DMEM AT > IMEM
  __data_load_start = LOADADDR(.data);

  .user0_bss (NOLOAD) : ALIGN(16) {
    __user0_bss_start = .;
    *(.user0_bss .user0_bss.*)
    __user0_bss_end = .;
  } > USER0_DMEM

  .user1_bss (NOLOAD) : ALIGN(16) {
    __user1_bss_start = .;
    *(.user1_bss .user1_bss.*)
    __user1_bss_end = .;
  } > USER1_DMEM

  .user2_bss (NOLOAD) : ALIGN(16) {
    __user2_bss_start = .;
    *(.user2_bss .user2_bss.*)
    __user2_bss_end = .;
  } > USER2_DMEM

  .user3_bss (NOLOAD) : ALIGN(16) {
    __user3_bss_start = .;
    *(.user3_bss .user3_bss.*)
    __user3_bss_end = .;
  } > USER3_DMEM

  .bss (NOLOAD) : ALIGN(4) {
    __bss_start = .;
    *(.sbss .sbss.*)
    *(.bss .bss.*)
    *(COMMON)
    __bss_end = .;
  } > KERNEL_DMEM

  .noinit (NOLOAD) : ALIGN(4) {
    *(.noinit .noinit.*)
  } > KERNEL_DMEM

  __stack_top = ORIGIN(KERNEL_DMEM) + LENGTH(KERNEL_DMEM);
  __global_pointer$ = __data_start + 0x800;

  /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.eh_frame*) }
}
