/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# eRISCV MCU Zifencei product test: DBus patches executable IMEM.
# The target instruction initially clears x31. DBus overwrites it with
# addi x31, x0, 42; fence.i must force a refetch of the updated word.

  .section .text
  .globl _start
  .option norvc
_start:
  la t0, target
  li t1, 0x02a00f93      # addi x31, x0, 42
  sw t1, 0(t0)
  fence.i

target:
  addi x31, x0, 0
pass:
  j pass
