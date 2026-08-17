/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# External debug halt/resume smoke test.
#
# The testbench asserts debug_halt_req_i while this program is running,
# waits for debug_halted_o, then resumes execution through debug_resume_req_i.

  addi x1, x0, 1
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  nop
  addi x2, x0, 2
  addi x3, x1, 3
done:
  jal  x0, done
