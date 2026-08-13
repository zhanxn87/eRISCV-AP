/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "eriscv_mcu.h"

#define FPU_DMA_WORDS 4u

static volatile eriscv_mcu_u32 source[FPU_DMA_WORDS] ERISCV_MCU_SYSTEM_SRAM_BUFFER;
static volatile eriscv_mcu_u32 destination[FPU_DMA_WORDS] ERISCV_MCU_SYSTEM_SRAM_BUFFER;
static volatile eriscv_mcu_u32 zcf_slot ERISCV_MCU_SYSTEM_SRAM_BUFFER;

static eriscv_mcu_u32 fp_add_bits(eriscv_mcu_u32 left_bits,
                                  eriscv_mcu_u32 right_bits)
{
  union {
    eriscv_mcu_u32 bits;
    float value;
  } left, right, sum;

  left.bits = left_bits;
  right.bits = right_bits;
  sum.value = left.value + right.value;
  return sum.bits;
}

static eriscv_mcu_u32 fp_divide_by_zero_flags(void)
{
  volatile float numerator = 1.0f;
  volatile float denominator = 0.0f;
  volatile float quotient;

  eriscv_mcu_fp_clear_fflags();
  quotient = numerator / denominator;
  (void)quotient;
  return eriscv_mcu_fp_read_fflags();
}

static eriscv_mcu_u32 zcf_stack_round_trip(eriscv_mcu_u32 bits)
{
  eriscv_mcu_u32 copy;

  __asm__ volatile (
      "addi sp, sp, -16\n\t"
      "fmv.w.x ft0, %1\n\t"
      "c.fswsp ft0, 0(sp)\n\t"
      "c.flwsp ft1, 0(sp)\n\t"
      "fmv.x.w %0, ft1\n\t"
      "addi sp, sp, 16"
      : "=&r"(copy)
      : "r"(bits)
      : "ft0", "ft1", "memory");
  return copy;
}

static eriscv_mcu_u32 zcf_system_sram_round_trip(eriscv_mcu_u32 bits)
{
  eriscv_mcu_u32 copy;

  __asm__ volatile (
      "mv a0, %2\n\t"
      "fmv.w.x fa0, %1\n\t"
      "c.fsw fa0, 0(a0)\n\t"
      "c.flw fa1, 0(a0)\n\t"
      "fmv.x.w %0, fa1"
      : "=&r"(copy)
      : "r"(bits), "r"(&zcf_slot)
      : "a0", "fa0", "fa1", "memory");
  return copy;
}

int main(void)
{
  eriscv_mcu_u32 index;
  eriscv_mcu_u32 status;
  int result = ERISCV_MCU_DMA_OK;

	eriscv_mcu_uart_init(ERISCV_MCU_UART_DIVISOR);
  eriscv_mcu_gpio_set_direction(1u);

  source[0] = 0x3fc00000u;  /* 1.5f */
  source[1] = 0x40100000u;  /* 2.25f */
  source[2] = 0x40400000u;  /* 3.0f */
  source[3] = 0xc1200000u;  /* -10.0f */
  for (index = 0u; index < FPU_DMA_WORDS; ++index) {
    destination[index] = 0u;
  }

  __asm__ volatile ("fence rw, rw" ::: "memory");
  result = eriscv_mcu_dma_start((eriscv_mcu_u32)(unsigned long)source,
                                (eriscv_mcu_u32)(unsigned long)destination,
                                FPU_DMA_WORDS * sizeof(source[0]), 0);
  if (result == ERISCV_MCU_DMA_OK) {
    result = eriscv_mcu_dma_wait(10000u);
  }
  status = eriscv_mcu_dma_status();
  if (result == ERISCV_MCU_DMA_OK &&
      (status & ERISCV_MCU_DMA_STATUS_DONE) == 0u) {
    result = ERISCV_MCU_DMA_EIO;
  }
  for (index = 0u; result == ERISCV_MCU_DMA_OK && index < FPU_DMA_WORDS; ++index) {
    if (destination[index] != source[index]) {
      result = ERISCV_MCU_DMA_EIO;
    }
  }

  if (result == ERISCV_MCU_DMA_OK) {
    eriscv_mcu_fp_enable();
    if (fp_add_bits(destination[0], destination[1]) != 0x40700000u ||
        zcf_stack_round_trip(destination[2]) != destination[2] ||
        zcf_system_sram_round_trip(destination[3]) != destination[3] ||
        (fp_divide_by_zero_flags() & ERISCV_MCU_FFLAGS_DZ) == 0u ||
        (eriscv_mcu_fp_read_fcsr() & ERISCV_MCU_FFLAGS_DZ) == 0u ||
        (eriscv_mcu_fp_read_mstatus() & ERISCV_MCU_MSTATUS_FS_MASK) !=
            ERISCV_MCU_MSTATUS_FS_DIRTY) {
      result = ERISCV_MCU_DMA_EIO;
    }
  }

  eriscv_mcu_dma_clear_status();
  eriscv_mcu_gpio_write(result == ERISCV_MCU_DMA_OK ? 1u : (eriscv_mcu_u32)(-result));
  eriscv_mcu_uart_puts(result == ERISCV_MCU_DMA_OK ?
                      "eRISCV-M2 FPU DMA SRAM PASS\n" :
                      "eRISCV-M2 FPU DMA SRAM FAIL\n");
  for (;;) {
  }
}
