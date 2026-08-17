# SPDX-FileCopyrightText: 2025-2026 Xianning Zhan
# SPDX-License-Identifier: BSD-3-Clause

# SFENCE.VMA is legal in M-mode and serializes the local translation state.
.section .text
.option norvc
.globl _start
_start:
  .word 0x12000073              # sfence.vma x0, x0
  addi  a0, x0, 1
1:
  j     1b
