/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "string.h"
#include "stdlib.h"
#include "stdio.h"
#include "math.h"
#include "ctype.h"

int memcmp(const void *left, const void *right, size_t count) {
  const unsigned char *lhs = left;
  const unsigned char *rhs = right;

  while (count-- != 0u) {
    if (*lhs != *rhs) return (int)*lhs - (int)*rhs;
    ++lhs;
    ++rhs;
  }
  return 0;
}

size_t strlen(const char *s) {
  size_t n = 0;
  while (*s++) ++n;
  return n;
}

char *strchr(const char *s, int c) {
  while (*s) { if (*s == (char)c) return (char *)s; ++s; }
  return (char *)0;
}

void *memmove(void *dest, const void *src, size_t n) {
  unsigned char *d = dest;
  const unsigned char *s = src;
  if (d < s) { while (n--) *d++ = *s++; }
  else { d += n; s += n; while (n--) *--d = *--s; }
  return dest;
}

void exit(int status) { (void)status; for (;;) {} }
void abort(void) { for (;;) {} }
void *malloc(size_t size) { (void)size; return (void *)0; }
void free(void *ptr) { (void)ptr; }
int fprintf(FILE *stream, const char *format, ...) { (void)stream; (void)format; return 0; }
int printf(const char *format, ...) { (void)format; return 0; }
double sqrt(double x) { (void)x; return 0.0; }
double pow(double x, double y) { (void)x; (void)y; return 0.0; }
double fabs(double x) { return (x < 0.0) ? -x : x; }
float fabsf(float x) { return (x < 0.0f) ? -x : x; }
int isdigit(int c) { return (c >= '0' && c <= '9'); }
int isspace(int c) { return (c == ' ' || c == '\t' || c == '\n'); }
int isalpha(int c) { return ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')); }
int isxdigit(int c) { return isdigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'); }
int toupper(int c) { return (c >= 'a' && c <= 'z') ? (c - 'a' + 'A') : c; }
int tolower(int c) { return (c >= 'A' && c <= 'Z') ? (c - 'A' + 'a') : c; }
