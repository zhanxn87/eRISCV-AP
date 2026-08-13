/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

# Local debug-mode entry through EBREAK and return through DRET.
#
# The debug handler is placed at DEBUG_BASE_ADDR=0x100. The main program sets
# dcsr.ebreakm, executes EBREAK, and resumes at the instruction after EBREAK.
# The handler checks dpc through x4 and writes dscratch0 so the main program can
# observe that debug CSR state was accessible while in debug mode.

  addi  x1, x0, 1
  lui   x5, 0x8
  csrrw x0, dcsr, x5
  ebreak
  addi  x2, x0, 2
  csrrs x6, dscratch0, x0
done:
  jal   x0, done

  .org 0x100
debug_handler:
  addi  x3, x0, 3
  csrrs x4, dpc, x0
  addi  x7, x0, 7
  csrrw x0, dscratch0, x7
  dret
