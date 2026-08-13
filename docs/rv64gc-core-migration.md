# eRISCV-AP RV64GC Core Migration Contract

## Status

In progress.  The existing `rtl/riscv_core` implementation is being widened
in place; this is not a statement that it already implements RV64GC.

## Architectural target

- One in-order, scalar RV64GC hart.
- Five-stage integer pipeline (`IF -> ID -> EX -> MEM -> WB`) with explicit
  stall/replay for long-latency operations.
- `M/S/U` privilege modes.  Sv39, L1 caches, and the DDR/AXI subsystem are
  separate integration milestones; they are not assumed by the core-only
  implementation.
- `G` means `I`, `M`, `A`, `F`, `D`, `Zicsr`, and `Zifencei`; `C` remains
  required. Zba/Zbb/Zbs, Zicond, and Zcf are not part of the target and their
  copied M2 encodings must trap as illegal instructions. No M2-only debug,
  PMP, DMA, or TCM capability is implicitly part of this target.

## Core boundary

The RV64 core owns architectural register state, instruction decode,
exceptions, privilege state, integer and floating-point execution, and LSU
request generation.  It must not depend on an M2 ITCM/DTCM/System-SRAM
address map or on a Xilinx-specific DDR interface.

The downstream memory interface must carry a 64-bit data path, byte strobes,
error response, and enough request identity/state to support the future
cache-line adapter.  Cacheability, MMIO bypass, Sv39 translation, and AXI4
burst adaptation are intentionally outside the first width-conversion
milestone.

The architectural PC, GPR address arithmetic, and trap values are 64 bits.
The initial MMU target is Sv39 (`VADDR_W = 39`), whose virtual addresses must
be canonical; the first downstream physical-memory interface is limited to
48 bits (`PADDR_W = 48`).  The current 32-bit M2 memory ports are a migration
artifact and must be replaced by a 64-bit-data, 48-bit-physical-address
interface rather than silently truncating an architectural address.

## Required conversion order

1. **RV64I/M data path** — GPR, pipeline packets, ALU, branches, `OP-IMM-32`,
   `OP-32`, RV64 load/store widths and sign-extension, RV64 multiply/divide,
   64-bit PC/address and debug transport.  Add focused directed tests before
   removing RV32 checks.
2. **Privileged RV64 baseline** — RV64 CSR widths and `misa`; preserve precise
   exceptions and interrupt behavior.  M2 M/U/PMP behavior is a reference,
   not a compatibility contract.
3. **A extension** — AMO and LR/SC require an explicit atomic LSU interface,
   reservation state, alignment/access-fault rules, and invalidation rules for
   future DMA writes.  Do not implement them as ordinary load/store sequences.
4. **F/D** — widen the FPR file to `32 x 64`, configure FPnew for RV64D,
   implement NaN boxing and all F/D decode/conversion/compare/move semantics,
   then validate FCSR and precise retirement.
5. **S-mode and Sv39** — delegation, supervisor CSRs and traps, `satp`, ITLB,
   DTLB, PTW, access/page faults, and `SFENCE.VMA`.
6. **Memory-system integration** — I$/D$, cache-line interface, independent
   AXI masters, MMIO bypass/APB bridge, DDR4/MIG, then Ethernet DMA
   non-coherence policy.

## Non-negotiable verification gates

- RV64 compliance/profile tests compiled with `-march=rv64gc -mabi=lp64d`.
- Directed coverage for `*W` instructions, `LW` vs `LWU`, `LD`/`SD`, shift
  amounts 32--63, upper-half multiply results, divide corner cases, and
  sign-extended 32-bit writeback.
- A-extension LR/SC and AMO tests, including reservation invalidation.
- F/D tests for FP64 arithmetic, NaN boxing, conversions, exceptions, and
  load/store.
- Privilege/MMU tests for S/U transitions, delegation, Sv39 page faults, and
  fence/flush interactions.

## Explicitly deferred

- Superscalar issue, out-of-order execution, cache coherence, multicore, vector
  extension, and custom ISA extensions.
- Reusing the M2 SoC as the AP SoC.  M2 RTL remains a bootstrap reference only.
