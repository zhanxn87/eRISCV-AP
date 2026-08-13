/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "eriscv_mcu.h"

/*
 * Single-precision LINPACK-derived measurement.
 *
 * The timed path is scalar LU decomposition with partial pivoting followed by
 * one back-substitution.  It follows the classic LINPACK operation convention
 * of 2/3*N^3 + 2*N^2 floating-point operations per solve. N=100 is the
 * classic LINPACK order; the cycle-accurate simulation default is N=32.
 * This is not an
 * official LINPACK result: official report entries require 64-bit arithmetic,
 * while eRISCV-M2 implements RV32F binary32 only.
 */
#ifndef LINPACK_ORDER
#define LINPACK_ORDER       100u
#endif
#define LINPACK_REPORT_MAGIC 0x4c504631u
#define LINPACK_REPORT_PASS  0x80000001u
#define LINPACK_REPORT_FAIL  0x40000001u
#define LINPACK_ERROR_LIMIT  0.001f

typedef struct {
  volatile eriscv_mcu_u32 done;
  eriscv_mcu_u32 magic;
  eriscv_mcu_u32 order;
  eriscv_mcu_u32 repetitions;
  eriscv_mcu_u32 start;
  eriscv_mcu_u32 stop;
  eriscv_mcu_u32 solve_cycles;
  eriscv_mcu_u32 max_error_bits;
  eriscv_mcu_u32 fflags;
} linpack_report_t;

volatile linpack_report_t eriscv_linpack_sp_report;
static float matrix[LINPACK_ORDER][LINPACK_ORDER];
static float rhs[LINPACK_ORDER];
static eriscv_mcu_u32 pivot[LINPACK_ORDER];

static eriscv_mcu_u32 read_mcycle(void)
{
  eriscv_mcu_u32 value;

  __asm__ volatile ("csrr %0, mcycle" : "=r"(value) :: "memory");
  return value;
}

static float absf(float value)
{
  return (value < 0.0f) ? -value : value;
}

static eriscv_mcu_u32 f32_bits(float value)
{
  union {
    eriscv_mcu_u32 bits;
    float value;
  } convert;

  convert.value = value;
  return convert.bits;
}

static eriscv_mcu_u32 next_random(eriscv_mcu_u32 *state)
{
  *state = (*state * 1664525u) + 1013904223u;
  return *state;
}

/* Generate a deterministic, diagonally dominant A with x = 1 as its solution. */
static void matgen(void)
{
  eriscv_mcu_u32 random_state = 0x13579bdfu;
  eriscv_mcu_u32 row;

  for (row = 0u; row < LINPACK_ORDER; ++row) {
    float sum = 0.0f;
    eriscv_mcu_u32 column;

    for (column = 0u; column < LINPACK_ORDER; ++column) {
      eriscv_mcu_u32 random_word = next_random(&random_state);
      float element = ((float)((random_word >> 8) & 0xffffu) / 65536.0f) - 0.5f;

      if (row == column)
        element += 10.0f;
      matrix[row][column] = element;
      sum += element;
    }
    rhs[row] = sum;
  }
}

static void swap_rows(eriscv_mcu_u32 first, eriscv_mcu_u32 second)
{
  eriscv_mcu_u32 column;

  if (first == second)
    return;
  for (column = 0u; column < LINPACK_ORDER; ++column) {
    float temporary = matrix[first][column];

    matrix[first][column] = matrix[second][column];
    matrix[second][column] = temporary;
  }
}

/* Keep the timed factorization and solve visible in the disassembly. */
static int __attribute__((noinline)) sgefa(void)
{
  eriscv_mcu_u32 column;

  for (column = 0u; column < LINPACK_ORDER - 1u; ++column) {
    eriscv_mcu_u32 candidate = column;
    float maximum = absf(matrix[column][column]);
    eriscv_mcu_u32 row;

    for (row = column + 1u; row < LINPACK_ORDER; ++row) {
      float magnitude = absf(matrix[row][column]);

      if (magnitude > maximum) {
        candidate = row;
        maximum = magnitude;
      }
    }
    pivot[column] = candidate;
    if (maximum == 0.0f)
      return -1;
    swap_rows(column, candidate);
    for (row = column + 1u; row < LINPACK_ORDER; ++row) {
      float multiplier = matrix[row][column] / matrix[column][column];
      eriscv_mcu_u32 trailing;

      matrix[row][column] = multiplier;
      for (trailing = column + 1u; trailing < LINPACK_ORDER; ++trailing)
        matrix[row][trailing] -= multiplier * matrix[column][trailing];
    }
  }
  pivot[LINPACK_ORDER - 1u] = LINPACK_ORDER - 1u;
  return (matrix[LINPACK_ORDER - 1u][LINPACK_ORDER - 1u] == 0.0f) ? -1 : 0;
}

static void __attribute__((noinline)) sgesl(void)
{
  eriscv_mcu_u32 column;

  for (column = 0u; column < LINPACK_ORDER - 1u; ++column) {
    eriscv_mcu_u32 row;
    float temporary = rhs[pivot[column]];

    rhs[pivot[column]] = rhs[column];
    rhs[column] = temporary;
    for (row = column + 1u; row < LINPACK_ORDER; ++row)
      rhs[row] -= matrix[row][column] * temporary;
  }
  for (column = LINPACK_ORDER; column != 0u; --column) {
    eriscv_mcu_u32 row;
    eriscv_mcu_u32 diagonal = column - 1u;
    float temporary;

    rhs[diagonal] /= matrix[diagonal][diagonal];
    temporary = -rhs[diagonal];
    for (row = 0u; row < diagonal; ++row)
      rhs[row] += temporary * matrix[row][diagonal];
  }
}

static float verify_solution(void)
{
  eriscv_mcu_u32 random_state = 0x13579bdfu;
  float maximum_error = 0.0f;
  eriscv_mcu_u32 row;

  for (row = 0u; row < LINPACK_ORDER; ++row) {
    float expected_rhs = 0.0f;
    float solved_rhs = 0.0f;
    eriscv_mcu_u32 column;

    for (column = 0u; column < LINPACK_ORDER; ++column) {
      eriscv_mcu_u32 random_word = next_random(&random_state);
      float element = ((float)((random_word >> 8) & 0xffffu) / 65536.0f) - 0.5f;

      if (row == column)
        element += 10.0f;
      expected_rhs += element;
      solved_rhs += element * rhs[column];
    }
    {
      float error = absf(solved_rhs - expected_rhs);

      if (error > maximum_error)
        maximum_error = error;
    }
  }
  return maximum_error;
}

int main(void)
{
  eriscv_mcu_u32 repetition;
  eriscv_mcu_u32 start;
  eriscv_mcu_u32 stop;
  eriscv_mcu_u32 solve_cycles = 0u;
  float maximum_error;
  int status = 0;

  eriscv_linpack_sp_report.done = 0u;
  eriscv_linpack_sp_report.magic = LINPACK_REPORT_MAGIC;
  eriscv_linpack_sp_report.order = LINPACK_ORDER;
  eriscv_linpack_sp_report.repetitions = LINPACK_REPETITIONS;
	eriscv_mcu_uart_init(ERISCV_MCU_UART_DIVISOR);
  eriscv_mcu_fp_enable();

  for (repetition = 0u; repetition < LINPACK_REPETITIONS; ++repetition) {
    matgen();
    /* Report only flags raised by the final timed solve, not setup/verification. */
    eriscv_mcu_fp_clear_fflags();
    start = read_mcycle();
    status |= sgefa();
    sgesl();
    stop = read_mcycle();
    solve_cycles += stop - start;
  }
  maximum_error = verify_solution();

  eriscv_linpack_sp_report.start = start;
  eriscv_linpack_sp_report.stop = stop;
  eriscv_linpack_sp_report.solve_cycles = solve_cycles;
  eriscv_linpack_sp_report.max_error_bits = f32_bits(maximum_error);
  eriscv_linpack_sp_report.fflags = eriscv_mcu_fp_read_fflags();
  if ((status != 0) || (maximum_error > LINPACK_ERROR_LIMIT)) {
    eriscv_linpack_sp_report.done = LINPACK_REPORT_FAIL;
    eriscv_mcu_uart_puts("eRISCV-M2 SP Linpack FAIL\n");
  } else {
    eriscv_linpack_sp_report.done = LINPACK_REPORT_PASS;
    eriscv_mcu_uart_puts("eRISCV-M2 SP Linpack PASS\n");
  }
  for (;;) {
  }
}
