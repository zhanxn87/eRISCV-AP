/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# Single-step debug smoke test.
#
# The program enters debug mode through EBREAK with dcsr.step set. The first
# DRET resumes at the instruction after EBREAK, one instruction retires, and
# step entry redirects back to the debug handler with dcsr.cause=4. The second
# handler pass clears dcsr.step before DRET so the main program can finish.

  addi  x1, x0, 1
  lui   x5, 0x8
  addi  x5, x5, 4
  csrrw x0, dcsr, x5
  ebreak
  addi  x2, x0, 2
  csrrs x6, dscratch0, x0
done:
  jal   x0, done

  .org 0x100
debug_handler:
  csrrs x9, dscratch0, x0
  addi  x9, x9, 1
  csrrw x0, dscratch0, x9
  addi  x11, x0, 2
  bne   x9, x11, debug_return
  addi  x5, x0, 4
  csrrc x0, dcsr, x5
debug_return:
  dret
