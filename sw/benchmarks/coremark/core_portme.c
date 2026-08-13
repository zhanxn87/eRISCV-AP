/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include <stdarg.h>

#include "coremark.h"
#include "eriscv_mcu.h"

volatile ee_u32 eriscv_coremark_result;
ee_u32 default_num_contexts = 1u;

volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;
static ee_u32 start_cycles;
static ee_u32 stop_cycles;
static int validation_failed;

static ee_u32 read_mcycle(void) {
  ee_u32 value;
  __asm__ volatile ("csrr %0, mcycle" : "=r"(value));
  return value;
}

static int starts_with(const char *text, const char *prefix) {
  while (*prefix != '\0') {
    if (*text++ != *prefix++) return 0;
  }
  return 1;
}

static int contains(const char *text, const char *needle) {
  const char *candidate;
  const char *probe;
  if (*needle == '\0') return 1;
  while (*text != '\0') {
    candidate = text;
    probe = needle;
    while (*candidate != '\0' && *probe != '\0' && *candidate == *probe) {
      ++candidate;
      ++probe;
    }
    if (*probe == '\0') return 1;
    ++text;
  }
  return 0;
}

static void emit_char(char value) {
  eriscv_mcu_uart_putc(value);
}

static void emit_unsigned(unsigned long value, unsigned int base, int width, int zero_pad) {
  char buffer[16];
  int count = 0;
  const char *digits = "0123456789abcdef";
  do {
    buffer[count++] = digits[value % base];
    value /= base;
  } while (value != 0ul);
  while (count < width) {
    emit_char(zero_pad ? '0' : ' ');
    --width;
  }
  while (count != 0) emit_char(buffer[--count]);
}

static void record_validation_error(const char *format) {
  if (starts_with(format, "ERROR! Must execute")) return;
  if (starts_with(format, "Cannot validate") ||
      contains(format, "ERROR! ") || starts_with(format, "ERROR:")) {
    validation_failed = 1;
  }
}

int ee_printf(const char *format, ...) {
  va_list args;
  const char *text;
  int width;
  int zero_pad;
  int is_long;
  int count = 0;

  record_validation_error(format);
  va_start(args, format);
  while (*format != '\0') {
    if (*format != '%') {
      emit_char(*format++);
      ++count;
      continue;
    }
    ++format;
    zero_pad = 0;
    width = 0;
    if (*format == '0') {
      zero_pad = 1;
      ++format;
    }
    while (*format >= '0' && *format <= '9') {
      width = width * 10 + (*format++ - '0');
    }
    is_long = (*format == 'l');
    if (is_long) ++format;
    switch (*format++) {
      case '%': emit_char('%'); ++count; break;
      case 'c': emit_char((char)va_arg(args, int)); ++count; break;
      case 's':
        text = va_arg(args, const char *);
        if (text == NULL) text = "<NULL>";
        while (*text != '\0') { emit_char(*text++); ++count; }
        break;
      case 'd':
      case 'i': {
        long value = is_long ? va_arg(args, long) : va_arg(args, int);
        if (value < 0) { emit_char('-'); ++count; value = -value; }
        emit_unsigned((unsigned long)value, 10u, width, zero_pad);
        break;
      }
      case 'u':
        emit_unsigned(is_long ? va_arg(args, unsigned long) : va_arg(args, unsigned int),
                      10u, width, zero_pad);
        break;
      case 'x':
      case 'X':
        emit_unsigned(is_long ? va_arg(args, unsigned long) : va_arg(args, unsigned int),
                      16u, width, zero_pad);
        break;
      default: emit_char('?'); ++count; break;
    }
  }
  va_end(args);
  return count;
}

void start_time(void) {
  start_cycles = read_mcycle();
}

void stop_time(void) {
  stop_cycles = read_mcycle();
}

CORE_TICKS get_time(void) {
  return stop_cycles - start_cycles;
}

secs_ret time_in_secs(CORE_TICKS ticks) {
  return ticks / COREMARK_CLOCK_HZ;
}

void portable_init(core_portable *p, int *argc, char *argv[]) {
  (void)argc;
  (void)argv;
	eriscv_mcu_uart_init(ERISCV_MCU_UART_DIVISOR);
  eriscv_coremark_result = 0u;
  validation_failed = 0;
  p->portable_id = 1u;
}

void portable_fini(core_portable *p) {
  ee_u32 status = validation_failed ? 0x40000000u : 0x80000000u;
  eriscv_coremark_result = status | (get_time() & 0x3fffffffu);
  p->portable_id = 0u;
}
