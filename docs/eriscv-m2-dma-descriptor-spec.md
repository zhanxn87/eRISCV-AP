# eRISCV-M2 Generic DMA Descriptor v1

## Scope

This is the frozen software/RTL contract for the generic-DMA descriptor
engine.  M2 implements both register-programmed System SRAM copies and linked
descriptor fetch. Ethernet, Wi-Fi, and other peripheral DMA masters are
independent and do not reuse this binary descriptor format.

## Placement and layout

- A descriptor is 32 bytes, 32-byte aligned, little-endian, and resides wholly
  in System SRAM.
- Software declares one with `eriscv_mcu_dma_descriptor_t` and
  `ERISCV_MCU_DMA_DESCRIPTOR`; the BSP enforces the 32-byte C layout at build
  time.
- `next`, `source`, and `destination` must be naturally aligned System SRAM
  addresses. `length` is a non-zero multiple of four bytes for v1.
- `next == 0` terminates a chain. `END` additionally declares that the
  descriptor is terminal; hardware reports an error if `END` and non-zero
  `next` disagree.

| Word | Byte offset | Field | Software before ownership | Hardware completion result |
| --- | --- | --- | --- | --- |
| 0 | `0x00` | `next` | Next descriptor or zero | unchanged |
| 1 | `0x04` | `source` | Source buffer address | unchanged |
| 2 | `0x08` | `destination` | Destination buffer address | unchanged |
| 3 | `0x0c` | `length` | Requested byte count | unchanged |
| 4 | `0x10` | `control` | `OWN`, `IRQ_EN`, `END`, `SRC_INC`, `DST_INC` | `OWN` cleared |
| 5 | `0x14` | `status` | zero | `DONE` or `ERROR` |
| 6 | `0x18` | `bytes_transferred` | zero | completed byte count |
| 7 | `0x1c` | `reserved` | zero | zero |

## Ownership and ordering

1. Software initializes every field except `control.OWN`, with `status` and
   `bytes_transferred` cleared.
2. Software executes `fence rw, rw`, then sets `OWN` last. It must not modify
   an owned descriptor.
3. Hardware accepts only owned descriptors, clears `OWN`, writes status and
   byte count, then latches the descriptor event when `IRQ_EN` is set.
4. Software observes completion only after `OWN == 0` and a `fence rw, rw`.
   `DONE` and `ERROR` are mutually exclusive.

No cache or cacheable alias exists on M2, so no cache-maintenance operation is
part of this contract.  The ordering fences remain mandatory so the ABI stays
valid if execution ordering changes.

An unowned `DESC_HEAD` or `next` descriptor is rejected with channel `ERROR`
and is not modified. Other malformed owned descriptors are completed with
descriptor `ERROR`, zero bytes transferred, and cleared `OWN`.

## v1 limits

- Generic DMA permits System SRAM-to-System SRAM transfers only; firewall
  rejection sets `ERROR` and terminates the current descriptor.
- `SRC_INC` and `DST_INC` are required for v1 memory copies. Their clear form
  is reserved for a later peripheral endpoint extension.
- `next` is validated before fetch. Chains are limited to 256 accepted
  descriptors; an overlong chain completes the current descriptor with
  `ERROR` and terminates. A loop cannot refetch a completed descriptor because
  its `OWN` bit has already been cleared; the revisit terminates with channel
  `ERROR` and does not modify that unowned descriptor.

## DMA MMIO mode selection

`CTRL.START` starts the existing direct register mode (`SRC`, `DST`, `LEN`).
`CTRL.DESC_START` starts descriptor mode at 32-byte-aligned `DESC_HEAD`.
Software must choose exactly one start bit per command. `CTRL.IRQ_EN` gates
the source-5 PLIC line for both modes.

Descriptor `IRQ_EN` sets sticky `STATUS.DESC_IRQ` after that descriptor's
writeback. It may fire before the chain becomes idle. Software clears it with
`STATUS.DESC_IRQ` W1C; `DONE` is set only after a terminal descriptor and
`ERROR` terminates the chain. The BSP entry point is
`eriscv_mcu_dma_start_descriptor()`.

`CTRL.ABORT` stops the active transfer after any already accepted System SRAM
request returns. For an owned descriptor, hardware then clears `OWN`, writes
descriptor `ERROR`, and writes the count of successfully completed payload
bytes before setting channel `ERROR`. A descriptor fetch that has not reached
an owned descriptor is not modified.

## Focused evidence

`dma_system_sram_tb` covers successful linked copies, malformed and unowned
descriptors, payload bus error, abort writeback, loop revisit, and a 257-entry
chain that exercises the 256-entry limit. `dma_descriptor_irq_wfi` proves the
descriptor event through PLIC source 5, MEI, and WFI. These are focused tests,
not a full SoC or timing closure.
