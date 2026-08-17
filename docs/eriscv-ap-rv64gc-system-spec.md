# eRISCV-AP RV64GC System Architecture Specification

## Status and authority

This document is the normative architecture target for eRISCV-AP.  It turns
the high-level diagrams in [eRISCV-AP V3](eRISCV-AP%20V3-64B.png) and
[eRISCV-AP Arch](eRISCV-AP%20Arch-64B.png) into an implementation and verification
contract.

The normative target is a composable application-processor platform with a
private hart tile, a shared memory system, a peripheral subsystem, and a
separate Ethernet subsystem. The current RTL implements that shallow SoC
boundary: `ap_soc.sv` composes `ap_cluster`, `ap_memory_system`,
`ap_peripheral_subsystem`, and `ap_ethernet_subsystem`. `ap_cluster` owns the
shared Boot ROM. `ap_hart_tile` is the canonical per-hart integration unit; its
`core/riscv_core` execution submodule and `mem/ap_hart_memory_frontend` are
stored together under `rtl/soc/hart_tile/`. The frontend owns hart-local Sv39,
cache, and physical-routing state and exports cached `axi_mem` plus uncached
`axi_periph` managers. `ap_memory_system` exports DDR only and locally returns DECERR for
non-DDR traffic; it is not a peripheral path.

The peripheral slave complex is now integrated for the single-hart RTL:
`axi_periph` routes local device traffic through the AXI-to-APB bridge; the APB
decoder selects CLINT, PLIC, and low-speed peripherals, while BPI terminates
in an AXI4-to-asynchronous-x16 NOR controller that drives SoC BPI pins. The VCU108 C1 DDR4 MIG source XCI is
checked in; its board wrapper, AP-address rebase, 64-to-512 AXI adaptation,
reset/calibration integration and multi-hart coherence remain follow-on work.  The
portable Ethernet DMA path is integrated at the SoC GMII boundary; board PCS/PMA
integration remains follow-on work. The core has an M/S/U trap baseline, end-to-end Sv39 I/D
request plumbing, and tested `SATP`, `SFENCE.VMA`, ITLB/DTLB/PTW/fault paths.
No 32-bit TCM map, generic MCU DMA, legacy M2 APB fabric, M2 clock controller,
or M2 watchdog reset tree is part of the AP SoC manifest.

## Product contract

- One scalar, in-order RV64GC hart with a five-stage integer pipeline:
  `IF -> ID -> EX -> MEM -> WB`.
- ISA target: `RV64GC` plus `Zicbom`: `I`, `M`, `A`, `F`, `D`, `C`, `Zicsr`,
  `Zifencei`, and cache-block `CBO.INVAL`, `CBO.CLEAN`, `CBO.FLUSH`.
- `Zicboz` and `Zicbop` are not implemented. Firmware/DTB must publish the
  fixed 64-byte CBO block size when it advertises `Zicbom`.
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
│       ├── core/riscv_core (RV64GC execution pipeline)
│       └── ap_hart_memory_frontend
│           ├── ITLB, DTLB, shared PTW, and Sv39 fault control
│           ├── private I-Cache and D-Cache
│           └── cached and uncached physical AXI master ports
├── ap_memory_system
│   ├── ap_axi_mem_xbar (I-Cache, D-Cache, Ethernet DMA)
│   ├── optional coherent L2 and directory
│   └── DDR4/MIG boundary
├── ap_peripheral_subsystem
│   ├── ap_axi_periph_xbar (APB, Flash/BPI, internal DECERR)
│   ├── AXI-to-APB bridge
│   └── CLINT, PLIC, and low-speed peripherals
└── ap_ethernet_subsystem
    ├── MAC control slave on APB
    ├── DMA master on memory AXI4
    ├── interrupt output to PLIC
    └── external PHY interface
```

Inside `ap_hart_tile`, `core/riscv_core` owns execution and architectural
state; `mem/ap_hart_memory_frontend` owns per-hart translation, cache, and
transaction state. Neither leaks into the shared SoC fabric. `ap_memory_system` owns only physical, cacheable memory
traffic and the external DDR boundary. `ap_peripheral_subsystem` owns uncached
device traffic. Ethernet spans both planes and is therefore a separate
subsystem rather than a child of either one.

### Two AXI fabrics

The target has two logically independent AXI4 domains. They may share a clock
and reset but do not share a cacheable/uncached ingress mux.

| Domain | Managers | Targets | Purpose |
| --- | --- | --- | --- |
| `axi_mem` | every hart I-Cache, every hart D-Cache, Ethernet DMA | `ap_axi_mem_xbar` -> coherent L2 if present, DDR4/MIG, DECERR | cache-line fills, write-backs, PTE reads, DMA descriptors and payloads |
| `axi_periph` | every hart uncached master | `ap_axi_periph_xbar` -> AXI-to-APB, Flash/BPI, internal DECERR | strongly ordered device/MMIO accesses |

The current single-hart RTL already routes its one uncached manager through
`ap_axi_periph_xbar`, configured with APB and Flash/BPI target ports; unmatched
requests terminate in PULP's internal DECERR slave.  The crossbar is the
manager-side expansion point for a multi-hart cluster; no second cacheable-memory
fabric is required.  `ap_memory_system` uses `ap_axi_mem_xbar` with three
manager ports and two targets (DDR and DECERR); it never exports or shares
`axi_periph`.

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

CLINT and PLIC are 32-bit APB slaves behind the 64-bit `axi_periph`
AXI-to-APB bridge. Their outputs bypass every register bus: CLINT drives each
hart's `mtime`, `msip`, and `mtip` inputs; PLIC drives distinct M/S context
`meip` and `seip` inputs directly. APB register latency therefore cannot delay
interrupt propagation.

The Ethernet MAC control register file is an APB slave. Its DMA is an
`axi_mem` manager and its interrupt is a PLIC source. The first DMA contract
is non-coherent: software owns D-Cache clean/invalidate operations for
shared buffers. A future coherent L2 may add an I/O coherence port without
changing the MAC control interface.

### Ethernet IP baseline and board split

The frozen MAC baseline is the MIT-licensed `alexforencich/verilog-ethernet`
revision `77320a9471d19c7dd383914bc049e02d9f4f1ffb`. AP vendors only the
self-contained 1G GMII MAC closure: `eth_mac_1g`, `axis_gmii_rx`,
`axis_gmii_tx`, and its CRC LFSR. The local module name `ap_eth_lfsr`
replaces the upstream generic `lfsr` solely to avoid collision with
`rtl/vendor/common_cells`; the vendor README records the exact delta.

The portable Ethernet subsystem terminates at a GMII boundary and owns
clock-domain crossings between SoC/DMA logic and the PCS clocks; it must not
assume that the SoC root clock is 125 MHz. The VCU108 wrapper owns the
Marvell M88E1111 SGMII PCS/PMA, LVDS reference clock, MDIO/MDC, PHY reset,
and SGMII pins. `fpga/vcu108/ip/gig_ethernet_pcs_pma/create_ip.tcl` is
the source-controlled Vivado PCS/PMA configuration, not generated IP output.

The SoC instantiates the initial Ethernet data plane: APB direct-buffer control,
64-bit AXI4 DMA, byte-stream clock-domain crossings, GMII MAC, and PLIC source 5.
The controller submits one posted TX buffer and one posted RX buffer at a time;
addresses must be eight-byte aligned; TX length is at most 1536 bytes and RX
capacity is at most 2048 bytes. A completed-DMA token crosses to the PHY clock
domain only after the whole TX frame reaches the asynchronous FIFO, so a faster
PHY cannot underflow GMII TX.
Descriptor rings, PHY management/link reporting, external D-Cache/reservation
invalidations, and the Linux driver are later control-plane work.

### Current transition implementation

Reset fetch is served by Boot ROM; DDR instruction fetch uses I-Cache. I-Cache
and D-Cache have distinct `axi_mem` managers, while the blocking uncached
master owns `axi_periph`. Ethernet DMA owns the third `axi_mem` manager and
reaches its APB register plane through the peripheral subsystem. `ap_memory_system` connects the cacheable managers to DDR and its
local DECERR terminator. `ap_peripheral_subsystem` accepts 64-bit uncached AXI requests through
`ap_axi_periph_xbar`. The crossbar maps CLINT, PLIC, and the APB aperture to
the local AXI-to-APB bridge; BPI maps to `ap_axi_bpi_nor`, which drives the
x16 asynchronous NOR pins. The first revision accepts aligned single-beat
64-bit reads, assembles four little-endian halfwords, and returns `SLVERR` for
writes; all other addresses complete through PULP axi_xbar's decode-error slave.

The following current tests exercise the actual SoC path, not only
elaboration:

- `make -C dv/soc/sim ap-soc-route`: Boot ROM -> I-Cache -> `axi_mem` -> DDR;
  it asserts an eight-beat 64-bit line fill at `AP_DDR_BASE`.
- `make -C dv/soc/sim ap-soc-flash-boot-regression`: no DDR preload; executes
  Boot ROM from reset, verifies the generated payload XOR64 while copying it
  from BPI to DDR, proves a self-modifying `FENCE.I` path and an exact
  multi-64-byte-line transfer, waits through a 64-cycle RY/BY# stall, and
  rejects corrupt magic/version/size/load/entry/checksum fields.
- `make -C dv/soc/sim ap-soc-flash-boot-sv39`: the same BPI/DDR boot path
  builds page tables in its DDR payload, enters S-mode with Sv39, and proves
  translated I/D accesses plus PTW A/D atomic updates.
- `make -C dv/soc/sim ap-soc-periph-route`: Boot ROM -> uncached
  `axi_periph` -> local AXI-to-APB UART path; it fails if a DDR read or BPI
  egress request is issued.
- `make -C dv/soc/sim ap-peripheral-subsystem`: 64-bit AXI lane splitting,
  CLINT APB `MSIP`/`MTIP`/`MTIME`, APB GPIO, Ethernet APB decode, PLIC APB M/S
  contexts, and BPI NOR read access.
- `make -C dv/soc/sim ap-ethernet-dma`: APB direct-buffer control, AXI64 DMA
  reads/writes, independent SoC/PHY-clock CDC, GMII TX preamble/SFD/payload/FCS,
  CRC-valid GMII RX, and DDR payload round-trip. It does not validate descriptor rings, board PCS/PMA,
  PHY management, Linux driver behavior, or cache coherency.

Implementation source for the AXI transport is the frozen
[PULP AXI](https://github.com/pulp-platform/axi) `v0.35.3` snapshot in
`rtl/vendor/axi/`; its matching `common_cells v1.21.0` dependency is vendored
locally. AP-owned AXI topology and bridge wrappers live in `rtl/soc/memory/axi/` and `rtl/soc/peripherals/{axi,apb,flash}/`.

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
BPI terminates in `ap_axi_bpi_nor`, which exposes a 26-bit x16 word address, read data pins, and CE#/OE#/WE#/RESET#/RYBY# control pins at `ap_soc`.

### Implemented APB sub-map

| Base | Device | PLIC source ID |
| --- | --- | ---: |
| `0x0000_1000_0000` | UART0 | 1 |
| `0x0000_1000_1000` | SPI0 | 2 |
| `0x0000_1000_2000` | timer0 | 3 |
| `0x0000_1000_3000` | GPIO0 | — |
| `0x0000_1000_4000` | WDT0 reserved | 4 reserved |
| `0x0000_1000_5000` | Ethernet MAC/DMA | 5; direct-buffer APB/DMA RTL |

PLIC context 0 (M) is at offset `0x0020_0000`; context 1 (S) is at
`0x0020_1000`. Ethernet is PLIC source ID 5. Its APB aperture at
`0x0000_1000_5000` controls the initial direct-buffer DMA engine.

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

### Zicbom cache-block maintenance

`Zicbom` is implemented for the fixed 64-byte L1 D-Cache block. `CBO.INVAL`,
`CBO.CLEAN`, and `CBO.FLUSH` use the `rs1` effective address, Sv39 translation,
and store permission/fault path; translation may set PTE.A but does not set
PTE.D. They are cache-maintenance transactions, never ordinary D-bus stores,
and never allocate a missing line. A clean writes a dirty resident line back, a
flush writes it back then invalidates it, and an invalidate discards a resident
line without writeback. The local cache owns only DDR lines, so a CBO to a
non-resident or non-DDR physical block completes without peripheral I/O.

M-mode always permits the operations. At reset, `menvcfg.CBIE=11` and
`menvcfg.CBCFE=1`, permitting S-mode native invalidate, clean, and flush.
`CBIE=01` changes S-mode `CBO.INVAL` into a flush, `CBIE=00` disables it, and
the reserved `CBIE=10` WARL write is coerced to `00`. Clear `CBCFE` to disable
S-mode clean/flush. U-mode CBOs are illegal until `senvcfg` is implemented;
the AP does not implement the hypervisor qualification CSRs.

For non-coherent DMA, software cleans a CPU-produced buffer before the device
reads it, and invalidates a device-produced buffer before the CPU reads it.
The required ownership transfer is fenced around the DMA descriptor/doorbell;
`CBO.FLUSH` is the conservative handoff when the CPU will not retain the line.
This is the current Ethernet DMA software contract.

### Atomics and external agents

RV64A is a cache responsibility at the memory-system boundary, not a sequence
of ordinary load/store accesses.

- `LR.W/D`, `SC.W/D`, and all base AMOs execute only in cacheable DDR.
- An AMO locks its cache line through read-modify-write completion.  `AMO.W`
  returns the sign-extended pre-operation 32-bit value; `AMO.D` returns the
  full 64-bit pre-operation value.
- The reservation granule is one D-Cache line.  An `LR` records that line;
  an overlapping core store, AMO, eviction, invalidate, or trap/reset clears it.
  The current SoC has no external invalidation source.  `SC` returns zero on success and
  one on failure.
- Ethernet DMA is non-coherent. Before TX, software cleans the physical DDR buffer
  (`CBO.CLEAN`, then `FENCE`); after RX completion, it invalidates the buffer
  (`CBO.INVAL`, then `FENCE`) before CPU consumption. The current hardware does
  not inject external D-Cache or LR/SC-reservation invalidations, so software
  must not execute LR/SC or race cached accesses while a buffer is device-owned.
  A coherent L2/directory remains the future alternative for multi-hart cache
  sharing or an I/O-coherent DMA port.
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
- The initial implementation exposes one uncached manager. `ap_axi_periph_xbar`
  is the explicit arbitration and address-decode boundary for future hart
  managers; DMA does not share the peripheral fabric.

### Transitional transport

The current cacheable-memory fabric accepts up to eight outstanding
transactions and may reorder responses across IDs. PULP crossbar links append
ingress-route bits internally; `ap_axi_mem_xbar` maps them back to the required
4-bit DDR/error boundary with `axi_iw_converter`. This transport detail is not
the final subsystem API.

## Boot and Linux target

The implemented first-stage Boot ROM assumes that board DDR reset/calibration
has already completed. It reads a 64-byte little-endian BPI header (magic,
version, payload length, DDR load address, entry address, and XOR64 payload
checksum), validates that the eight-byte-aligned payload fits the AP DDR
aperture, verifies the checksum while copying it with aligned 64-bit BPI
reads, executes `FENCE.I`, and jumps to the DDR entry. The XOR64 check detects
accidental corruption; it is not image authentication. `sw/ap_bootrom/`
generates the ROM and x16 BPI images consumed by the boot regressions; their
payloads are bare-metal verification programs, not OpenSBI.

The production sequence is Boot ROM -> BPI package -> OpenSBI -> Linux with a
DTB and initramfs in DDR. DDR/MIG initialization, image authentication, a CFI
flash-programming path, and the OpenSBI/DTB handoff are not yet implemented.

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
   invalidation on overlapping local writes, eviction, invalidate, trap, and reset; and
7. I-Cache refill, same-line hit, and invalidation/refill; and
8. preservation of existing RV64I/M/F/D/C directed regressions.

Current evidence: `check-filelist` resolves the AP SoC manifest;
`tile-smoke`, `ap-soc-route`, `ap-soc-flash-boot-regression`,
`ap-soc-flash-boot-sv39`, `ap-soc-periph-route`, `ap-soc-sv39-route`,
`ap-soc-sv39-fault`, and `ap-peripheral-subsystem` pass; and `rv64-directed`
passes the RV64 core, ALU/control-flow, M, load/store, C, F/D move, F/D, A,
FENCE, S-mode, and SFENCE.VMA directed tests. The S-mode/SATP CSR test and
focused Sv39 PTE, PTW, TLB, and MMU-controller tests pass; `ap-ethernet-dma`
passes the APB-to-AXI DMA and GMII data path. These checks do not validate
board-level DDR/MIG adaptation, flash program/erase or CFI behavior, Ethernet
descriptor rings/PHY/Linux coherency, firmware/DTB, FPGA timing, or Linux boot.

## Implementation sequence

1. **Done:** remove the TCM/early-local-load integration from the AP top; use
   the D-Cache CPU-side interface and AP-only RTL manifest.
2. **Done:** implement and unit-test blocking 32 KiB/2-way/64-byte I-Cache and
   D-Cache with 512-bit, 64-bit-AXI line transport.
3. **Done:** extract `ap_hart_tile`, `ap_cluster`, `ap_memory_system`,
   `ap_peripheral_subsystem`, and `ap_ethernet_subsystem`; split `axi_mem` and
   `axi_periph`; remove the shared cache/MMIO mux; and add direct hart-tile and SoC routing smoke tests; place every private hart
   implementation module below `rtl/soc/hart_tile/`.
4. **Done:** implement M/S/U supervisor trap state, delegation, S-level
   interrupt state, supervisor CSR access rules, and `SRET`, with directed
   synchronous and interrupt-delegation tests.
5. **Done:** integrate the implemented `satp`/ITLB/DTLB/PTW controller at
   the core-facing I/D boundaries with precise instruction/load/store
   page/access-fault plumbing and MPRV effective privilege.
6. **Done (local peripherals and MIG source):** integrate 64-bit
   `axi_periph` lane handling, AXI-to-APB, CLINT, M/S PLIC contexts,
   UART0/SPI0/timer0/GPIO0, the read-only x16 BPI NOR controller, its generated
   first-stage boot image, and the VCU108 C1 MIG source XCI. **Next:** the AP
   board wrapper (DDR rebase, 64-to-512 adapter, and calibration reset), BPI
   CFI/program-erase support, OpenSBI, and DTB.
7. **Done (initial Ethernet data plane):** vendor the MIT 1G MAC source closure,
   source-control the VCU108 SGMII PCS/PMA configuration, and integrate APB
   direct-buffer control, non-coherent AXI4 DMA, CDC, GMII MAC, PLIC source 5,
   and MAC-level TX/RX simulation. **Next:** descriptor rings, PHY management,
   Linux Zicbom buffer-ownership driver ABI, and board PCS/PMA integration; add
   L2/directory before any multi-hart private write-back D-Cache configuration.
