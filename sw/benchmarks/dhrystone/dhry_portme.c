/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

/*
 * dhry_portme.c — eRISCV-M2 bare-metal Dhrystone port layer.
 *
 * Provides mcycle-based timing, UART output, and a minimal printf.
 */
#include "dhry.h"
#include "dhry_portme.h"
#include "eriscv_mcu.h"

static unsigned int start_cycles;
static unsigned int stop_cycles;
#if DHRY_HPM
static unsigned int start_instret;
static unsigned int stop_instret;
static unsigned int hpm_inhibit_saved;
static struct dhry_hpm_counts hpm_counts;
#endif

/* ---- mcycle access ---- */
static unsigned int read_mcycle(void) {
  unsigned int value;
  __asm__ volatile ("csrr %0, mcycle" : "=r"(value));
  return value;
}

#if DHRY_HPM
static unsigned int read_minstret(void) {
  unsigned int value;
  __asm__ volatile ("csrr %0, minstret" : "=r"(value));
  return value;
}

static unsigned int read_mhpmcounter3(void) {
  unsigned int value;
  __asm__ volatile ("csrr %0, mhpmcounter3" : "=r"(value));
  return value;
}

static unsigned int read_mhpmcounter4(void) {
  unsigned int value;
  __asm__ volatile ("csrr %0, mhpmcounter4" : "=r"(value));
  return value;
}

static unsigned int read_mhpmcounter5(void) {
  unsigned int value;
  __asm__ volatile ("csrr %0, mhpmcounter5" : "=r"(value));
  return value;
}

static unsigned int read_mhpmcounter6(void) {
  unsigned int value;
  __asm__ volatile ("csrr %0, mhpmcounter6" : "=r"(value));
  return value;
}

static void hpm_prepare_window(void) {
  unsigned int inhibit;

  __asm__ volatile ("csrr %0, mcountinhibit" : "=r"(inhibit));
  hpm_inhibit_saved = inhibit;
  inhibit |= 0x78u;
  __asm__ volatile ("csrw mcountinhibit, %0" :: "r"(inhibit));

  __asm__ volatile ("csrw mhpmevent3, %0" :: "r"(4u));
  __asm__ volatile ("csrw mhpmevent4, %0" :: "r"(8u));
  __asm__ volatile ("csrw mhpmevent5, %0" :: "r"(9u));
  __asm__ volatile ("csrw mhpmevent6, %0" :: "r"(11u));
  __asm__ volatile ("csrw mhpmcounter3, zero");
  __asm__ volatile ("csrw mhpmcounter4, zero");
  __asm__ volatile ("csrw mhpmcounter5, zero");
  __asm__ volatile ("csrw mhpmcounter6, zero");
  __asm__ volatile ("csrw mhpmcounter3h, zero");
  __asm__ volatile ("csrw mhpmcounter4h, zero");
  __asm__ volatile ("csrw mhpmcounter5h, zero");
  __asm__ volatile ("csrw mhpmcounter6h, zero");
}

static void hpm_enable_window(void) {
  unsigned int inhibit = hpm_inhibit_saved & ~0x78u;
  __asm__ volatile ("csrw mcountinhibit, %0" :: "r"(inhibit));
}

static void hpm_disable_window(void) {
  unsigned int inhibit = hpm_inhibit_saved | 0x78u;
  __asm__ volatile ("csrw mcountinhibit, %0" :: "r"(inhibit));
}

static void hpm_restore_configuration(void) {
  __asm__ volatile ("csrw mcountinhibit, %0" :: "r"(hpm_inhibit_saved));
}
#endif

char *strcpy(char *restrict destination, const char *restrict source) {
  char *result = destination;

  while ((*destination++ = *source++) != '\0') {
  }
  return result;
}

int strcmp(const char *left, const char *right) {
  while (*left == *right) {
    if (*left == '\0') {
      return 0;
    }
    ++left;
    ++right;
  }
  return (unsigned char)*left - (unsigned char)*right;
}

/* ---- port init ---- */
void dhry_port_init(void) {
	eriscv_mcu_uart_init(ERISCV_MCU_UART_DIVISOR);
  eriscv_dhrystone_result = 0u;
#if DHRY_HPM
  for (unsigned int index = 0; index < DHRY_HPM_REPORT_WORDS; ++index) {
    eriscv_dhrystone_hpm_report[index] = 0u;
  }
#endif
}

/* ---- timer ---- */
void dhry_port_start_time(void) {
#if DHRY_HPM
  hpm_prepare_window();
#endif
  start_cycles = read_mcycle();
  __asm__ volatile (
      ".global eriscv_dhrystone_profile_begin\n"
      "eriscv_dhrystone_profile_begin:\n"
      ::: "memory");
#if DHRY_HPM
  start_instret = read_minstret();
  hpm_enable_window();
#endif
}

void dhry_port_stop_time(void) {
  __asm__ volatile (
      ".global eriscv_dhrystone_profile_end\n"
      "eriscv_dhrystone_profile_end:\n"
      ::: "memory");
  stop_cycles = read_mcycle();
#if DHRY_HPM
  stop_instret = read_minstret();
  hpm_disable_window();
  hpm_counts.instret = stop_instret - start_instret;
  hpm_counts.branch_taken = read_mhpmcounter3();
  hpm_counts.ifetch_wait = read_mhpmcounter4();
  hpm_counts.data_wait = read_mhpmcounter5();
  hpm_counts.load_use_stall = read_mhpmcounter6();
  hpm_restore_configuration();
#endif
}

unsigned int dhry_port_get_cycles(void) {
  return stop_cycles - start_cycles;
}

#if DHRY_HPM
void dhry_port_get_hpm_counts(struct dhry_hpm_counts *counts) {
  *counts = hpm_counts;
}
#endif

/* ---- raw UART output ---- */
void dhry_port_puts(const char *s) {
  while (*s != '\0') {
    eriscv_mcu_uart_putc(*s++);
  }
}

static void emit_char(char c) {
  eriscv_mcu_uart_putc(c);
}

void dhry_port_put_unsigned(unsigned long value, unsigned int base,
                            unsigned int width, int zero_pad) {
  char buf[16];
  int  count = 0;
  const char *digits = "0123456789abcdef";
  do {
    buf[count++] = digits[value % base];
    value /= base;
  } while (value != 0ul);
  while ((unsigned int)count < width) {
    emit_char(zero_pad ? '0' : ' ');
    --width;
  }
  while (count != 0) emit_char(buf[--count]);
}

/* ---- minimal printf (enough for Dhrystone) ---- */
#include <stdarg.h>

int dhry_port_vprintf(const char *fmt, va_list args) {
  int count = 0;
  const char *s;
  int width, zero_pad;
  unsigned long ulval;
  long lval;

  while (*fmt != '\0') {
    if (*fmt != '%') {
      emit_char(*fmt++);
      ++count;
      continue;
    }
    ++fmt;
    zero_pad = 0;
    width = 0;
    if (*fmt == '0') { zero_pad = 1; ++fmt; }
    while (*fmt >= '0' && *fmt <= '9') {
      width = width * 10 + (*fmt++ - '0');
    }
    switch (*fmt++) {
      case '%': emit_char('%'); ++count; break;
      case 'c': emit_char((char)va_arg(args, int)); ++count; break;
      case 's':
        s = va_arg(args, const char *);
        if (s == 0) s = "<NULL>";
        while (*s != '\0') { emit_char(*s++); ++count; }
        break;
      case 'd':
      case 'i':
        lval = va_arg(args, int);
        if (lval < 0) { emit_char('-'); ++count; lval = -lval; }
        dhry_port_put_unsigned((unsigned long)lval, 10u, (unsigned int)width, zero_pad);
        break;
      case 'u':
        ulval = va_arg(args, unsigned int);
        dhry_port_put_unsigned(ulval, 10u, (unsigned int)width, zero_pad);
        break;
      case 'x':
        ulval = va_arg(args, unsigned int);
        dhry_port_put_unsigned(ulval, 16u, (unsigned int)width, zero_pad);
        break;
      default: emit_char('?'); ++count; break;
    }
  }
  return count;
}
