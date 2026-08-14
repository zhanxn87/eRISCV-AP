# eRISCV-AP RV64GC System Architecture Specification

## Status and authority

This document is the normative architecture target for eRISCV-AP.  It turns
the high-level diagrams in [eRISCV-AP V3](eRISCV-AP%20V3-64B.png) and
[eRISCV-AP Arch](eRISCV-AP%20Arch-64B.png) into an implementation and verification
contract.

The normative target is a composable application-processor platform with a
private hart tile, a shared memory system, a peripheral subsystem, and a
separate Ethernet subsystem. The current RTL implements that shallow SoC
boundary: `soc.sv` composes `ap_cluster`, `ap_memory_system`,
`ap_peripheral_subsystem`, and `ap_ethernet_subsystem`. `ap_hart_tile` owns the
Boot ROM, RV64GC core, physical I/D caches, `axi_mem` managers, and the
independent uncached `axi_periph` manager. `ap_memory_system` exports DDR only
and locally returns DECERR for non-DDR traffic; it is not a peripheral path.

The peripheral slave complex, DDR/MIG integration, S-mode/Sv39, Ethernet DMA,
and multi-hart coherence are **planned**. A planned feature is binding for
subsequent work but is not delivered RTL. No 32-bit TCM map, generic MCU DMA,
legacy APB fabric, PLIC, CLINT, debug block, or clock controller is part of the
current AP SoC RTL manifest.

## Product contract

- One scalar, in-order RV64GC hart with a five-stage integer pipeline:
  `IF -> ID -> EX -> MEM -> WB`.
- ISA target: `RV64GC` only: `I`, `M`, `A`, `F`, `D`, `C`, `Zicsr`, and
  `Zifencei`.
- `Zba`, `Zbb`, `Zbs`, `Zicond`, `Zcf`, custom instructions, and all other
  non-target extensions are not AP ISA.  Their encodings trap as illegal.
- PMP is not implemented and is not an AP requirement.
- Architectural XLEN is 64. Physical addresses are 48 bits. The virtual
  address target is canonical Sv39; S-mode, Sv39, ITLB/DTLB, and a shared PTW
  are hart-tile functions planned after the L1-cache transport is established.
- The initial product has one hart. `AP_HART_COUNT` is a future cluster
  parameter; a second private write-back D-Cache is forbidden until a coherent
  L2/directory path is present.
- The target privilege architecture is M/S/U.  Until S-mode is delivered,
  the existing machine-mode bootstrap is not a Linux-capable system.

## Top-level structure

The long-term hierarchy is deliberately shallow at the SoC boundary:

```text
ap_soc
├── ap_cluster
│   └── ap_hart_tile[0..AP_HART_COUNT-1]
│       ├── RV64GC core
│       ├── ITLB, DTLB, shared PTW, and Sv39 fault control
│       ├── private I-Cache and D-Cache
│       └── cached and uncached physical AXI master ports
├── ap_memory_system
│   ├── memory AXI4 fabric
│   ├── optional coherent L2 and directory
│   └── DDR4/MIG boundary
├── ap_peripheral_subsystem
│   ├── peripheral AXI4 decode
│   ├── AXI-to-APB bridge
│   └── CLINT, PLIC, and low-speed peripherals
└── ap_ethernet_subsystem
    ├── MAC control slave on APB
    ├── DMA master on memory AXI4
    ├── interrupt output to PLIC
    └── external PHY interface
```

`ap_hart_tile` owns all per-hart architectural state. Translation and cache
control must not leak into the shared SoC fabric. `ap_memory_system` owns only
physical, cacheable memory traffic and external DDR. `ap_peripheral_subsystem`
owns uncached device traffic. Ethernet spans both planes and is therefore a
separate subsystem rather than a child of either one.

### Two AXI fabrics

The target has two logically independent AXI4 domains. They may share a clock
and reset but do not share a cacheable/uncached ingress mux.

| Domain | Managers | Targets | Purpose |
| --- | --- | --- | --- |
| `axi_mem` | every hart I-Cache, every hart D-Cache, Ethernet DMA | coherent L2 if present, DDR4/MIG | cache-line fills, write-backs, PTE reads, DMA descriptors and payloads |
| `axi_periph` | every hart uncached master | AXI-to-APB bridge, boot/control slaves | strongly ordered device/MMIO accesses |

The initial single-hart peripheral path may be a one-manager address decoder
rather than a general crossbar. A multi-hart build requires a peripheral
interconnect, but not a second cacheable-memory fabric. The current RTL already
has the separate planes at the subsystem boundary. Internally,
`ap_memory_system` uses a three-ingress/two-egress transport only for DDR plus
a local DECERR terminator; it never exports or shares `axi_periph`.

### Address translation and cacheability

With `satp` translation enabled, all hart instruction and data virtual
addresses translate before physical address decode:

```text
instruction VA -> ITLB -> physical PC -> Boot ROM or I-Cache
load/store VA  -> DTLB -> physical PA -> D-Cache or uncached peripheral path
```

MMIO never enters D-Cache, but it must not bypass DTLB when translation is
enabled. The DTLB performs VA-to-PA translation and permission checks; the
translated physical address and SoC PMA/address map decide whether the access
is cacheable DDR or an uncached device. `satp=Bare` is a physical-address
pass-through. M-mode data accesses are likewise direct unless `mstatus.MPRV`
selects a translated effective privilege.

The L1 caches remain physically indexed and physically tagged because
translation precedes their physical interfaces. ITLB and DTLB cache translations
by virtual page number and ASID. A shared PTW serves both; its page-table-entry
reads use a dedicated low-priority, cacheable D-Cache port and physical
addresses, so the walker never recursively passes through DTLB. `SFENCE.VMA`
invalidates selected translation entries. `FENCE.I` controls instruction-cache
visibility and does not invalidate TLBs.

### Interrupt and Ethernet placement

CLINT and PLIC register accesses may use APB. Their outputs must bypass APB:
CLINT drives each hart's `mtime`/`msip` inputs and PLIC drives each hart
context's `meip` input directly. APB latency therefore affects register
access, not interrupt propagation.

The Ethernet MAC control register file is an APB slave. Its DMA is an
`axi_mem` manager and its interrupt is a PLIC source. The first DMA contract
is non-coherent: software owns D-Cache clean/invalidate operations for
shared buffers. A future coherent L2 may add an I/O coherence port without
changing the MAC control interface.

### Current transition implementation

Reset fetch is served by Boot ROM; DDR instruction fetch uses I-Cache. I-Cache
and D-Cache have distinct `axi_mem` managers, while the blocking uncached
master owns `axi_periph`. Ethernet DMA retains a reserved idle `axi_mem`
manager. `ap_memory_system` connects the cacheable managers to DDR and its
local DECERR terminator. `ap_peripheral_subsystem` is currently an AXI
pass-through boundary; its AXI-to-APB decoder and device slaves are pending.

The following current tests exercise the actual SoC path, not only
elaboration:

- `make -C dv/soc/sim ap-soc-route`: Boot ROM -> I-Cache -> `axi_mem` -> DDR;
  it asserts an eight-beat 64-bit line fill at `AP_DDR_BASE`.
- `make -C dv/soc/sim ap-soc-periph-route`: Boot ROM -> uncached
  `axi_periph`; it asserts an uncached single-beat APB-aperture read and fails
  if a DDR read is issued.

Implementation source for the AXI transport is the frozen
[PULP AXI](https://github.com/pulp-platform/axi) `v0.35.3` snapshot in
`rtl/vendor/axi/`; its matching `common_cells v1.21.0` dependency is vendored
locally. AP-owned topology and bridge wrappers live in `rtl/soc/axi/`.

## Physical address map

All addresses below are 48-bit physical addresses.  A region not listed here
returns an access error; it must never be truncated into a legacy 32-bit
window.

| Base | Size | Region | Attributes |
| --- | ---: | --- | --- |
| `0x0000_0000_0000` | 64 KiB | Boot ROM | executable, read-only, uncached |
| `0x0000_0001_0000` | 64 KiB | CLINT | device, uncached |
| `0x0000_0002_0000` | 64 KiB | PLIC | device, uncached |
| `0x0000_0010_0000` | 16 MiB | APB MMIO aperture | device, uncached |
| `0x0000_0100_0000` | 128 MiB | BPI NOR flash | boot/storage; uncached until an XIP policy is specified |
| `0x0000_8000_0000` | 4 GiB | DDR4 main memory | cacheable, read/write |

The DDR range is `0x0000_8000_0000` through `0x0001_7fff_ffff`.  It replaces
the legacy local data memories as the normal CPU data-memory target.  There is no
AP architectural DTCM aperture.

The stated APB aperture (`0x0010_0000`--`0x010f_ffff`) overlaps the stated BPI
aperture at `0x0100_0000`--`0x010f_ffff`. This specification does not assign
priority for that overlap. The initial AXI fabric therefore exposes one
non-DDR peripheral egress and deliberately does not implement the secondary
Boot/CLINT/PLIC/APB/BPI decoder. Resolve the overlap before that decoder is
implemented; silently selecting either target is not permitted.

## L1 cache architecture

### Target geometry

Both L1 caches have the following target geometry:

| Property | I-Cache | D-Cache |
| --- | ---: | ---: |
| Capacity | 32 KiB | 32 KiB |
| Associativity | 2-way set associative | 2-way set associative |
| Cache line | 64 bytes | 64 bytes |
| Fill/write-back AXI burst | 8 x 64-bit beats | 8 x 64-bit beats |
| Policy | read-only | write-back, write-allocate |

The 64-byte line is a fixed contract from the AP architecture diagrams. It
defines the 512-bit cache-line interface and must not be silently changed to a
32-byte line.

### Implemented blocking-cache milestone

The initial cache milestone implements physical I/D caches before TLB or DDR
controller integration.

- I-Cache CPU-side request: one aligned 32-bit instruction word at a time,
  48-bit physical address, blocking response. It is read-only, 32 KiB, two-way,
  64-byte-line, and uses eight-beat 64-bit AXI refills.
- Boot ROM serves reset fetches; only DDR instruction fetches enter I-Cache.
  Unmapped instruction fetches currently return a NOP as a transition behavior.
  The final hart-tile contract requires an instruction-access fault instead.
- D-Cache CPU-side request: one accepted 64-bit request at a time, 48-bit
  physical address, 64-bit write data, eight byte strobes, read/write/error
  response, and an RV64A atomic-op field.
- Cacheable region: DDR4 only.
- Uncached region: Boot ROM, CLINT, PLIC, APB, and BPI flash.  These accesses
  bypass the D-Cache and retain ordering; AMO/LR/SC to them returns an access
  error.
- A load hit responds from the selected line.  A store hit updates the line
  and dirty state according to its byte strobes.
- A miss evicts a dirty victim before an eight-beat refill. The original CPU
  request completes only after the refill and requested line operation finish.
- The initial controller is blocking: one miss, eviction, refill, or atomic
  transaction is in flight.  A store buffer, multiple miss-status entries,
  and speculative load bypass are later performance work, not prerequisites
  for correctness.
- `FENCE` drains all pending D-Cache writeback work before retirement. The
  current implementation conservatively invalidates I-Cache for both `FENCE`
  and `FENCE.I` after the D-Cache drain. The final interface must distinguish
  D-Cache drain (`FENCE`) from instruction-cache invalidation (`FENCE.I`),
  while retaining the required `FENCE.I` ordering.

### Atomics and external agents

RV64A is a cache responsibility at the memory-system boundary, not a sequence
of ordinary load/store accesses.

- `LR.W/D`, `SC.W/D`, and all base AMOs execute only in cacheable DDR.
- An AMO locks its cache line through read-modify-write completion.  `AMO.W`
  returns the sign-extended pre-operation 32-bit value; `AMO.D` returns the
  full 64-bit pre-operation value.
- The reservation granule is one D-Cache line.  An `LR` records that line;
  an overlapping core store, AMO, eviction, invalidate, trap/reset, or an
  explicit external invalidation clears it.  `SC` returns zero on success and
  one on failure.
- Ethernet DMA and future masters are initially non-coherent. Before their
  RTL and Linux driver contract are accepted, no DMA may access cacheable
  buffers. The DMA specification must define clean/invalidate ownership and
  feed external-write invalidations to D-Cache reservation state. A coherent
  L2/directory is the required future alternative for multi-hart cache sharing
  or an I/O-coherent DMA port.
- Debug SBA accesses to DDR require a halted-hart cache-maintenance sequence;
  direct SBA reads are not guaranteed to observe dirty D-Cache lines.

## AXI4 contract

### Target `axi_mem` contract

- Separate read-only I-Cache and read/write D-Cache AXI4 manager ports feed
  the cacheable-memory fabric. Ethernet DMA is another `axi_mem` manager.
- AXI data width is 64 bits; the external physical-address width is 48 bits.
  AXI ID width is 4 bits at subsystem boundaries. An L1 line fill or
  write-back is `INCR`, `LEN=7`, and transfers eight 64-bit beats (64 bytes).
- A coherent L2/directory sits between multiple private write-back D-Caches
  and DDR. AXI alone supplies no cache coherence; direct parallel connection
  of multiple private D-Caches to DDR is prohibited.
- `axi_mem` errors propagate to the original CPU or DMA request. A failed dirty
  write-back must be reported and must not silently discard data.

### Target `axi_periph` contract

- An uncached hart request reaches `axi_periph` only after DTLB translation and
  physical-address classification. Device requests never pass through an L1
  cache and are strongly ordered.
- The APB bridge is a 32-bit uncached control/MMIO transport, not a cache
  backing store. CLINT/PLIC may sit behind that bridge; their interrupt outputs
  remain direct hart signals.
- The initial implementation may expose only one uncached manager. Multiple
  harts require arbitration in the peripheral subsystem; they do not require
  DMA to share the peripheral fabric.

### Transitional transport

The current cacheable-memory fabric accepts up to eight outstanding
transactions and may reorder responses across IDs. PULP crossbar links append
ingress-route bits internally; `ap_axi64_fabric` maps them back to the required
4-bit DDR/error boundary with `axi_iw_converter`. This transport detail is not
the final subsystem API.

## Boot and Linux target

Boot ROM initializes DDR through the platform memory controller, verifies and
loads the AP boot package from BPI NOR flash, then transfers control to
OpenSBI.  OpenSBI enters Linux with a DTB and initramfs in DDR.

Linux enablement requires, at minimum: S-mode, Sv39 with ITLB/DTLB/PTW
and precise page/access faults, I-Cache, D-Cache, CLINT, PLIC, a DDR-backed
physical-memory map, boot firmware/DTB, and a non-coherent DMA
cache-maintenance contract. RV64GC decode or D-Cache alone is not a Linux-port
completion claim.

## Verification acceptance

The cache milestone is accepted only with focused simulation evidence for:

1. clean load hit, byte-strobed store hit, dirty eviction, refill, and
   write-back line contents;
2. AXI backpressure and read/write error propagation;
3. uncached MMIO bypass without speculative/repeated device reads;
4. `FENCE` completion against a pending dirty line;
5. RV64 `LD/SD/LW/LWU` over cache hit and miss paths;
6. LR/SC success and failure, all AMO.W/D operations, and reservation
   invalidation on overlapping local and external writes; and
7. I-Cache refill, same-line hit, and invalidation/refill; and
8. preservation of existing RV64I/M/F/D/C directed regressions.

Current evidence: `check-filelist` resolves 193 AP SoC sources;
`ap-soc-route` and `ap-soc-periph-route` pass; and `rv64-directed` passes the
RV64 core, ALU/control-flow, M, load/store, C, F/D move, F/D, A, and FENCE
directed tests. These checks do not validate DDR/MIG, device decode, S-mode,
or Linux boot.

## Implementation sequence

1. **Done:** remove the TCM/early-local-load integration from the AP top; use
   the D-Cache CPU-side interface and AP-only RTL manifest.
2. **Done:** implement and unit-test blocking 32 KiB/2-way/64-byte I-Cache and
   D-Cache with 512-bit, 64-bit-AXI line transport.
3. **Done:** extract `ap_hart_tile`, `ap_cluster`, `ap_memory_system`,
   `ap_peripheral_subsystem`, and `ap_ethernet_subsystem`; split `axi_mem` and
   `axi_periph`; remove the shared cache/MMIO mux; and add core-driven routing
   smoke tests.
4. **Next:** extend the core from M/U to M/S/U: supervisor trap state,
   delegation, S-level interrupt state, supervisor CSR access rules, and
   `SRET`. This is the prerequisite for real virtual memory.
5. **Then:** implement `satp`, canonical-address checks, `SFENCE.VMA`, ITLB,
   DTLB, shared PTW, and precise page/access faults while preserving physical
   cache interfaces below translation.
6. **Then:** integrate DDR/MIG, AXI-to-APB, CLINT, PLIC, boot firmware, and
   DTB.
7. **Then:** integrate non-coherent Ethernet DMA plus its Linux
   cache-maintenance ABI; add L2/directory before any multi-hart private
   write-back D-Cache configuration.
