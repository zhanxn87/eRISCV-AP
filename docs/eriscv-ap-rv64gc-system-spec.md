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
`ap_peripheral_subsystem`, and `ap_ethernet_subsystem`. `ap_cluster` owns the
shared Boot ROM. `ap_hart_tile` is a structural wrapper for `riscv_core` and
`ap_hart_memory_frontend`; that frontend owns the hart-local Sv39, cache, and
physical-routing state and exports cached `axi_mem` plus uncached `axi_periph`
managers. `ap_memory_system` exports DDR only and locally returns DECERR for
non-DDR traffic; it is not a peripheral path.

The peripheral slave complex is now integrated for the single-hart RTL:
`axi_periph` decodes local CLINT, PLIC, and APB devices, and forwards only BPI
to the external peripheral AXI egress. The VCU108 C1 DDR4 MIG source XCI is
checked in; its board wrapper, AP-address rebase, 64-to-512 AXI adaptation,
reset/calibration integration, Ethernet DMA, and multi-hart coherence remain
follow-on work. The core has an M/S/U trap baseline, end-to-end Sv39 I/D
request plumbing, and tested `SATP`, `SFENCE.VMA`, ITLB/DTLB/PTW/fault paths.
No 32-bit TCM map, generic MCU DMA, legacy M2 APB fabric, M2 clock controller,
or M2 watchdog reset tree is part of the AP SoC manifest.

## Product contract

- One scalar, in-order RV64GC hart with a five-stage integer pipeline:
  `IF -> ID -> EX -> MEM -> WB`.
- ISA target: `RV64GC` only: `I`, `M`, `A`, `F`, `D`, `C`, `Zicsr`, and
  `Zifencei`.
- `Zba`, `Zbb`, `Zbs`, `Zicond`, `Zcf`, custom instructions, and all other
  non-target extensions are not AP ISA.  Their encodings trap as illegal.
- PMP is not implemented and is not an AP requirement.
- Architectural XLEN is 64. Physical addresses are 48 bits. The virtual
  address target is canonical Sv39. `SATP`, `SFENCE.VMA`, ITLB/DTLB, and a
  shared PTW route virtual I/D requests and precise page/access faults through
  `ap_hart_memory_frontend`; the VCU108 MIG source is present, while its
  board-level DDR adaptation and firmware are separate follow-on work.
- The initial product has one hart. `AP_HART_COUNT` is a future cluster
  parameter; a second private write-back D-Cache is forbidden until a coherent
  L2/directory path is present.
- The target privilege architecture is M/S/U. Translation and the local
  interrupt/MMIO substrate are present, but Linux boot still requires DDR/MIG,
  OpenSBI, a DTB, boot media, and Ethernet/DMA software contracts.

## Top-level structure

The long-term hierarchy is deliberately shallow at the SoC boundary:

```text
ap_soc
├── ap_cluster
│   └── ap_hart_tile[0..AP_HART_COUNT-1]
│       ├── RV64GC core
│       └── ap_hart_memory_frontend
│           ├── ITLB, DTLB, shared PTW, and Sv39 fault control
│           ├── private I-Cache and D-Cache
│           └── cached and uncached physical AXI master ports
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

`riscv_core` owns architectural state; `ap_hart_memory_frontend` owns the
per-hart translation, cache, and transaction state. Neither leaks into the
shared SoC fabric. `ap_memory_system` owns only physical, cacheable memory
traffic and the external DDR boundary. `ap_peripheral_subsystem` owns uncached
device traffic. Ethernet spans both planes and is therefore a separate
subsystem rather than a child of either one.

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
selects a translated effective privilege. The current RTL implements this
PTE permission/bypass policy in `ap_hart_memory_frontend`, including
instruction, load, store, and page-table-walk access-fault responses.

The L1 caches remain physically indexed and physically tagged because
translation precedes their physical interfaces. ITLB and DTLB cache translations
by virtual page number and ASID. A shared PTW serves both; its page-table-entry
reads use a dedicated low-priority, cacheable D-Cache port and physical
addresses, so the walker never recursively passes through DTLB. `SFENCE.VMA`
implements the requested local TLB invalidation scope in the hart tile;
`FENCE.I` controls instruction-cache visibility and does not invalidate TLBs.

### Interrupt and Ethernet placement

CLINT and PLIC use the local 32-bit control transport behind the 64-bit
`axi_periph` slave; they are not routed through APB. Their outputs bypass every
register bus: CLINT drives each hart's `mtime`, `msip`, and `mtip` inputs;
PLIC drives distinct M/S context `meip` and `seip` inputs directly. Register
latency therefore cannot delay interrupt propagation.

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
local DECERR terminator. `ap_peripheral_subsystem` accepts 64-bit single-beat
uncached AXI requests, splits only selected 32-bit lanes into local accesses,
and decodes CLINT, PLIC, UART0, SPI0, timer0, and GPIO0. BPI is the sole
external `periph_axi_o` egress.

The following current tests exercise the actual SoC path, not only
elaboration:

- `make -C dv/soc/sim ap-soc-route`: Boot ROM -> I-Cache -> `axi_mem` -> DDR;
  it asserts an eight-beat 64-bit line fill at `AP_DDR_BASE`.
- `make -C dv/soc/sim ap-soc-periph-route`: Boot ROM -> uncached
  `axi_periph` -> local AXI-to-APB UART path; it fails if a DDR read or BPI
  egress request is issued.
- `make -C dv/soc/sim ap-peripheral-subsystem`: 64-bit AXI lane splitting,
  CLINT `MSIP`/`MTIP`/`MTIME`, APB GPIO, PLIC M/S contexts, and BPI egress.

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
| `0x0000_0200_0000` | 64 KiB | CLINT | device, uncached |
| `0x0000_0c00_0000` | 4 MiB | PLIC | device, uncached; M/S contexts |
| `0x0000_1000_0000` | 16 MiB | APB MMIO aperture | device, uncached |
| `0x0000_2000_0000` | 128 MiB | BPI NOR flash | boot/storage; uncached until an XIP policy is specified |
| `0x0000_8000_0000` | 2 GiB | DDR4 main memory | cacheable, read/write |

The DDR range is `0x0000_8000_0000` through `0x0000_ffff_ffff`, matching the
VCU108 C1 MIG source configuration. It replaces
the legacy local data memories as the normal CPU data-memory target. There is no
AP architectural DTCM aperture. All listed device windows are non-overlapping;
BPI is the only one forwarded to external `periph_axi_o`.

### Implemented APB sub-map

| Base | Device | PLIC source ID |
| --- | --- | ---: |
| `0x0000_1000_0000` | UART0 | 1 |
| `0x0000_1000_1000` | SPI0 | 2 |
| `0x0000_1000_2000` | timer0 | 3 |
| `0x0000_1000_3000` | GPIO0 | — |
| `0x0000_1000_4000` | WDT0 reserved | 4 reserved |

PLIC context 0 (M) is at offset `0x0020_0000`; context 1 (S) is at
`0x0020_1000`. Ethernet is reserved as PLIC source ID 5; its MAC/DMA remains
an idle placeholder, not a delivered device.

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

The initial cache milestone implements physical I/D caches below Sv39
translation and before board-level DDR controller integration.

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
  The VCU108 C1 MIG source has a 512-bit, 31-bit-local-address user AXI port;
  its board wrapper must subtract `AP_DDR_BASE` and adapt the portable 64-bit
  `axi_mem` interface. That wrapper is not yet implemented.
- A coherent L2/directory sits between multiple private write-back D-Caches
  and DDR. AXI alone supplies no cache coherence; direct parallel connection
  of multiple private D-Caches to DDR is prohibited.
- `axi_mem` errors propagate to the original CPU or DMA request. A failed dirty
  write-back must be reported and must not silently discard data.

### Target `axi_periph` contract

- An uncached hart request reaches `axi_periph` only after DTLB translation and
  physical-address classification. Device requests never pass through an L1
  cache and are strongly ordered.
- The local control transport is 32-bit and uncached, not a cache backing
  store. The AXI bridge issues only the 32-bit lanes selected by the RV64 byte
  enables, so narrow loads do not cause duplicate side-effecting reads.
  CLINT/PLIC interrupt outputs remain direct hart signals.
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

Linux enablement requires, at minimum: the delivered S-mode baseline plus Sv39
with ITLB/DTLB/PTW and precise page/access faults, I-Cache, D-Cache, CLINT,
PLIC, a DDR-backed
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

Current evidence: `check-filelist` resolves the AP SoC manifest;
`ap-soc-route`, `ap-soc-periph-route`, `ap-soc-sv39-route`,
`ap-soc-sv39-fault`, and `ap-peripheral-subsystem` pass; and `rv64-directed`
passes the RV64 core, ALU/control-flow, M, load/store, C, F/D move, F/D, A,
FENCE, S-mode, and SFENCE.VMA directed tests. The S-mode/SATP CSR test and
focused Sv39 PTE, PTW, TLB, and MMU-controller tests pass. These checks do not
validate board-level DDR/MIG adaptation, a production BPI controller,
Ethernet/DMA, firmware/DTB, FPGA timing, or Linux boot.

## Implementation sequence

1. **Done:** remove the TCM/early-local-load integration from the AP top; use
   the D-Cache CPU-side interface and AP-only RTL manifest.
2. **Done:** implement and unit-test blocking 32 KiB/2-way/64-byte I-Cache and
   D-Cache with 512-bit, 64-bit-AXI line transport.
3. **Done:** extract `ap_hart_tile`, `ap_cluster`, `ap_memory_system`,
   `ap_peripheral_subsystem`, and `ap_ethernet_subsystem`; split `axi_mem` and
   `axi_periph`; remove the shared cache/MMIO mux; and add core-driven routing
   smoke tests.
4. **Done:** implement M/S/U supervisor trap state, delegation, S-level
   interrupt state, supervisor CSR access rules, and `SRET`, with directed
   synchronous and interrupt-delegation tests.
5. **Done:** integrate the implemented `satp`/ITLB/DTLB/PTW controller at
   the core-facing I/D boundaries with precise instruction/load/store
   page/access-fault plumbing and MPRV effective privilege.
6. **Done (local peripherals and MIG source):** integrate 64-bit
   `axi_periph` lane handling, AXI-to-APB, CLINT, M/S PLIC contexts,
   UART0/SPI0/timer0/GPIO0, BPI egress, and the VCU108 C1 MIG source XCI.
   **Next:** the AP board wrapper (DDR rebase, 64-to-512 adapter, and
   calibration reset), a production BPI controller, boot firmware, and DTB.
7. **Then:** integrate non-coherent Ethernet DMA plus its Linux
   cache-maintenance ABI; add L2/directory before any multi-hart private
   write-back D-Cache configuration.
