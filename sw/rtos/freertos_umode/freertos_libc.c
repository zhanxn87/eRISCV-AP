/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#include "string.h"

void *memcpy(void *destination, const void *source, size_t count) {
  unsigned char *dst = destination;
  const unsigned char *src = source;

  while (count-- != 0u) *dst++ = *src++;
  return destination;
}

void *memset(void *destination, int value, size_t count) {
  unsigned char *dst = destination;

  while (count-- != 0u) *dst++ = (unsigned char)value;
  return destination;
}
