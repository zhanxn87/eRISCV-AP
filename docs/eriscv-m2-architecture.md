# eRISCV-M2 Architecture Contract

## Product Claim

`eriscv-m2` is a deterministic compute-and-data-movement MCU. Its fixed
contract is `RV32IMFC_Zicsr_Zifencei_Zicntr_Zihpm_Zihintpause_Zba_Zbb_Zbs_Zicond_Zcf`,
`ilp32f`, M/U modes, and 16 PMP entries.

## M2-Specific Architecture

- Preserve precise traps, interrupts, debug behavior, and the common
  PLIC/Debug 1.0 Minimal contract while adding the M2 core microarchitecture.
- Preserve the family `Zicntr`/`Zihpm` v2.0 contract: base counters plus
  exactly HPM3-HPM6; M-mode reads of unimplemented HPM7-HPM31 aliases return
  zero and writes are illegal. U-mode remains blocked by zero `mcounteren` bits.
- Integrate a pinned CVFPU/FPnew configuration for RV32F only: binary32
  operands/results, `f0`–`f31`, FCSR/`fflags`, and precise exception reporting
  at architectural commit. D, Zfa, vectors, and non-standard FP extensions are
  excluded. CVFPU and its required `common_cells` and `fpu_div_sqrt_mvp`
  snapshots are vendored below M2's own `rtl/vendor/`; their lock, provenance,
  hashes, and license records are part of the product source. The CVFPU
  snapshot includes one documented M2-local FMA underflow correctness patch;
  the [vendor lock](../rtl/vendor/cvfpu/LOCK.md) distinguishes that delta from
  the pinned upstream baseline.
- Provide directly addressed instruction TCM and data TCM. Their capacity,
  base address, arbitration, reset/initialization behavior, and access latency
  are fixed by the product integration contract below.
- Provide a separately decoded System SRAM and DMA controller. The implemented
  generic channel provides direct and linked-descriptor System SRAM copies,
  a fixed direct System-SRAM-to-UART0-TX byte-stream endpoint, source-5
  completion/error notification, and a System-SRAM firewall. UART RX, SPI,
  and Timer endpoints remain deferred. CPU PMP does not automatically
  constrain DMA.

## M2 Memory Configuration

| Region | Range | Capacity | Role |
| --- | --- | ---: | --- |
| ITCM | `0x1000_0000`--`0x1001_ffff` | 128 KiB | CPU-local executable SRAM |
| DTCM | `0x1100_0000`--`0x1101_ffff` | 128 KiB | CPU-local non-executable data SRAM |
| System SRAM | `0x8000_0000`--`0x8007_ffff` | 512 KiB | CPU/DMA shared non-executable buffer SRAM |
| DMA control | `0x5000_0000`--`0x5000_ffff` | 64 KiB window | DMA register block |

These are populated capacities within their existing architectural windows.
ITCM/DTCM remain outside DMA arbitration.

## System SRAM Topology

System SRAM is a logically contiguous, non-executable 512 KiB region.  It is
implemented as eight 64 KiB, 32-bit, single-port 1RW banks.  For a byte address
`a` in the System SRAM window, bank selection is `(a - 0x8000_0000)[4:2]` and
the local word index is `(a - 0x8000_0000)[18:5]`.  The bank interleave is not
visible to software: any buffer, descriptor ring, or packet may cross bank
boundaries.

- Each bank accepts at most one request per cycle.  Requests use a registered
  valid/ready admission and a registered response; no SRAM grant or response
  feeds the CPU issue, redirect, trap, or PMP combinational cones.
- Each bank owns an independent round-robin arbiter.  Requests to different
  banks proceed concurrently; requests to the same bank are serialized fairly.
  There is no global System-SRAM lock or central single-bank arbiter.
- The target ingress set is CPU DBus, generic DMA, Ethernet MAC DMA, Wi-Fi DMA,
  and debug/SBA. The current product wires only CPU DBus and generic DMA; the
  remaining ingress slots are reserved architectural interfaces, not
  implemented claims.
- ECC/error reporting, retention, and technology macro binding remain separate
  implementation decisions.  Any such addition must preserve the bank count,
  address mapping, and registered response contract.

Ethernet and Wi-Fi are independent System-SRAM bus masters; they must not be
serialized through the generic DMA controller.  Their RX/TX descriptors and
payload buffers reside only in System SRAM, never ITCM or DTCM.  M2 has no data
cache or cacheable alias, so no DMA cache-maintenance protocol is introduced.
Each MAC integration must provide enough ingress buffering for same-bank
arbitration delay and add its own completion/error interrupt source.

## PLIC Source Allocation

PLIC source IDs are product ABI.  A reserved source is tied low until its RTL
and directed test are integrated; its ID must not be reassigned.

| Source IDs | Allocation | Current state |
| --- | --- | --- |
| 1 | UART0 | wired |
| 2 | TIMER0 | wired |
| 3 | SPI0 | wired |
| 4 | WDT0 | wired |
| 5 | Generic DMA | wired |
| 6 | Ethernet MAC | reserved |
| 7 | Wi-Fi host/MAC | reserved |
| 8 | SDIO/eMMC | reserved |
| 9 | USB | reserved |
| 10 | I2S/PCM | reserved |
| 11 | Camera/CSI | reserved |
| 12 | ADC/DAC streaming | reserved |
| 13 | Crypto/accelerator | reserved |
| 14 | GPIO | reserved |
| 15 | CAN-FD | reserved |
| 16 | SoC control/PMU | reserved |
| 17--32 | Board and external expansion | reserved |

The external interrupt vector begins at source 17 and has 16 inputs.  DMA
completion/error is level-sensitive until its W1C status
is cleared, then software completes the PLIC claim. Descriptor completion can
also set `STATUS.DESC_IRQ`; `dma_descriptor_irq_wfi` proves the source-5
PLIC/MEI/WFI route.

## Timing and Pipeline Isolation

- Preserve the M1 integer fetch, branch/jump, load/store, and PMP timing
  boundaries. Neither DMA arbitration nor FPU completion may become a
  combinational input to their normal issue/redirect paths.
- Issue RV32F operations through the CVFPU valid/ready interface. The initial
  product slice adds no adapter boundary cycles; FPU completion is captured by
  the ordinary EX/MEM and WB commit packets carrying the result and FP
  exception flags. Add adapter boundary registers only if synthesis timing
  reports require them.
- Keep FMA and divide/square-root implementation latency inside the selected
  CVFPU configuration. Do not use an unpipelined or single-cycle FPU merely to
  reduce integration control logic.
- The first RV32F slice permits one outstanding transaction. A product-local
  adapter owns its tag, cancellation, and valid/ready conversion; CVFPU types
  never cross the adapter boundary.
- `FLW` and `FSW` reuse the existing LSU and therefore retain existing PMP,
  alignment, request, and error behavior.  The integer GPR file and the 32x32
  FP register file are distinct; FP forwarding/hazard control is distinct
  from GPR forwarding.
- `mstatus.FS`, `fflags`, `frm`, and `fcsr` are architectural state.  FP
  instructions are illegal while FS is Off; committed FP state changes set FS
  Dirty; IEEE flags accumulate only at the matching writeback commit.
- DMA and future MAC DMA masters own only the System SRAM/peripheral fabric.
  CPU accesses to ITCM/DTCM must not traverse System-SRAM arbitration. Register
  System SRAM request, grant, and response boundaries so DMA/MAC control
  fanout cannot enter CPU global redirect, trap, or PMP control paths.
- Treat M1's routed 100 MHz result as the initial floor, not spare margin:
  implementation must report integer-path WNS separately from FPU and DMA
  paths after each integration milestone.

## Generic DMA v1

The M2 generic DMA block has one channel at `0x5000_0000`. `START` selects
direct `SRC`/`DST`/`LEN` copies; with `CTRL.UART_TX`, it instead selects the
fixed `DST = UART0_BASE + TXDATA` byte stream. The UART source is 4-byte
aligned, bytes are emitted little-endian, and `LEN` is byte granular.
`DESC_START` selects a 32-byte-aligned System-SRAM-only linked list, limited to
256 accepted entries. Hardware clears `OWN`, writes terminal `DONE` or `ERROR`
plus `BYTES_TRANSFERRED`, and supports a drain-safe `ABORT` that reports any
completed payload bytes. It does not provide UART RX, SPI, Timer, stride,
arbitrary fixed-address peripheral, or cyclic-ring modes. The normative ABI is
[Generic DMA Descriptor v1](eriscv-m2-dma-descriptor-spec.md).

## Memory-System Rule

- ITCM, DTCM, and System SRAM are directly addressed performance memories.
- Do not implement instruction cache, data cache, cache controller, cache
  maintenance, DMA coherency, or cacheable aliases.
- Document all non-TCM instruction/data memory latency and bus-error behavior.

## Common Platform and Exclusions

`eriscv-m2` implements M/U modes, 16 PMP entries, MSIP/MTIP/MEIP, a 32-source
PLIC, the standard B extension (Zba/Zbb/Zbs), Zicond, and the complete Debug 1.0 Minimal baseline. Its debug RTL also includes
`mcontrol`/`icount` triggers and 32-bit DMEM DMI System Bus Access; program
buffer, trace, broader system-bus access, and FPR abstract access are deferred.
U-mode fetches and data accesses are PMP-enforced; MPRV and `mcounteren` follow
the common family contract. M2 excludes atomics, supervisor mode, AIA, `Zbc`,
cryptographic extensions, and custom ISA instructions.

The fixed APB platform provides UART0, GPIO0, TIMER0, SPI0, WDT0, and
clock/reset control in 64 KiB slots at `0x4000_0000` through `0x4005_0000`.
WDT0 pre-timeout is PLIC source 4; generic DMA completion/error is source 5.

M2 implements the complete standard B extension: Zba (`sh1add`, `sh2add`,
`sh3add`), Zbb, and Zbs. It also implements Zicond (`czero.eqz`,
`czero.nez`) for branchless conditional-zero operations. `Zbc` remains excluded.

`Zihintpause` is a fixed product extension. `pause` is legal and has no
required delay; the cacheless single-hart implementation retires it without
architectural side effects.

Its PLIC integration implements the common
[PLIC specification](../../docs/Spec/eriscv-mcu-plic-spec-v1.0.md), including the fixed
register map and source-allocation rules.
