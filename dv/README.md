# eRISCV-M2 Design Verification

This directory is the verification root for eRISCV-M2. Directed test collateral
is grouped with its core or SoC testbench.

This README is the maintained test inventory, including design intent,
execution flow, and oracle ownership. The dated full-regression totals are
owned by the [family evidence snapshot](../../docs/Verification/eriscv-mcu-simulation-evidence-snapshot.md).

| Directory | Content | Primary runner |
| --- | --- | --- |
| [`core/tests/`](core/tests/) | Core-directed product and inherited-baseline tests | `make -C eriscv-m2/dv/core/sim verilator` |
| [`soc/tests/`](soc/tests/) | MCU product integration, peripheral, interrupt, and debug tests | `make -C eriscv-m2/dv/soc/sim verilator` |
| ACT4 runtime cache (generated locally; see [`../compliance/riscv-arch-test/README.md`](../compliance/riscv-arch-test/README.md)) | Generated `.mem`, `.data.mem`, and `.act.json` collateral | `make act-generate-m2`, then `make -C eriscv-m2/dv/core/sim verilator TESTS=--act-full` |

## `core/tests/`

### MCU product tests

- `C/`: `MCU-C-01`, `MCU-C-DEBUG-STEP-SWEEP-01`, `MCU-C-DPC-01`,
  `MCU-C-IRQ-MEPC-01`, `MCU-C-LS-01`, `MCU-C-MIXED-PC-01`, `MCU-C-SP-01`.
  `MCU-C-IFETCH-CROSSWORD-01` is the core-level throughput guard for the
  C16-to-RV32 cross-word fetch compose path and precise trap recovery.
- `M/`: `MCU-M-01` covers all eight M operations plus divide-by-zero, signed overflow,
  `misa.M`, and an M-result dependency. `MCU-M-CTRL-01` covers a precise
  interrupt-during-MUL, back-to-back dependent consumers, ECALL return, and mixed
  MUL→DIV→REM sequencing. `MCU-M-DIV-IRQ-01` independently proves precise
  interrupt, restart, and dependent consumption for iterative DIV.
  `MCU-M-DIV-SHORT-01` covers leading-zero alignment plus signed/unsigned
  small-operand and equal-magnitude DIV/REM short paths.
- `LDST/`: `MCU-LOAD-RESP-BYPASS-01` proves one-cycle DTCM response retirement
  with an immediately dependent integer consumer.
- `RAS/`: `MCU-RAS-01` verifies nested x1/x5 call-return prediction and exact
  return architectural behavior.
- `BTFNT/`: `MCU-BTFNT-ID-01` covers native backward/forward prediction and
  both EX correction directions. `MCU-BTFNT-C-01` covers decompressed
  `C.BEQZ`/`C.BNEZ` plus ID-stage `C.J`/`C.JAL` redirects.
- `Zba/`: `MCU-ZBA-01` covers `sh1add`, `sh2add`, and `sh3add`, including XLEN
  wraparound, an `rd=x0` write suppression, register aliases, and back-to-back
  forwarding.
- `Zbb/`: `MCU-ZBB-01` covers all RV32 Zbb logical, count, min/max, extension,
  rotate, and byte operations, including zero-input count semantics and `misa.B`.
- `Zbs/`: `MCU-ZBS-01` covers each register and immediate bit set/clear/invert/
  extract form, including bit 31 and dependent consumers.
- `Zicond/`: `MCU-ZICOND-01` covers `czero.eqz` and `czero.nez` for both zero
  and nonzero conditions, including `x0` value operands.
- `PMP/`: `MCU-PMP-01` verifies the 16-entry PMP CSR address range, WARL and lock
  behavior, M-mode locked data permissions, and load/store/fetch access-fault reporting.
  `MCU-PMP-RESET-01` verifies reset values for all 16 pmpcfg/pmpaddr entries and
  post-reset M-mode access permission.
- `U/`: `MCU-UMODE-01` verifies M/U transition, U-mode ECALL and M-CSR traps,
  allowed U-mode data access, and PMP-denied U-mode load and instruction fetch.
  `MCU-UMODE-EXT-01` verifies MPRV's M-mode data-access effective privilege and
  `mcounteren` delegation and revocation for U-mode counter aliases.
- `HPM/`: `MCU-COUNTER-CSR-01` verifies the `mcountinhibit` mask, mcycle freeze/resume, and basic programmable HPM CSR/event access.
  `MCU-HPM-01` covers selector reset defaults, basic event-selection isolation,
  per-counter inhibit isolation, and 64-bit carry using explicitly programmed
  selectors. `MCU-HPM-CSR-01` covers the full `mcountinhibit` WARL mask,
  machine/URO low-and-high alias equality for mcycle/minstret/HPM3-HPM6,
  selector reserved-bit behavior, and `mcounteren` WARL masking. `MCU-HPM-TRAP-01` proves exact single-event
  counts for `BRANCH_TAKEN` and `EXCEPTION_TAKEN`; `MCU-HPM-IRQ-01` proves an
  exact `INTERRUPT_TAKEN` count using software-generated MSIP (no cycle-timed
  testbench IRQ). `MCU-HPM-WAIT-01` uses configured fetch/data latency to
  prove nonzero `IFETCH_WAIT_CYCLES`, `DATA_WAIT_CYCLES`,
  `PIPELINE_STALL_CYCLES`, and `LOAD_USE_STALL_CYCLES`, without constraining
  implementation-specific totals. `MCU-HPM-DEBUG-01` proves `DEBUG_ENTRY`
  through EBREAK/DRET; `MCU-HPM-PENDING-01` proves nonzero
  `IRQ_PENDING_CYCLES` while MIE remains disabled, isolating it from trap
  acceptance. They replace the retired `P8-HPM-01`.
- `WFI/`: `MCU-WFI-01` verifies that WFI holds younger execution until a machine
  external interrupt wakes the core, and that HPM6 configured for
  `WFI_CYCLES` observes a nonzero wait interval without assuming its cycle
  count.
- `Zifencei/`: `MCU-ZIFENCEI-01`, `MCU-ZIFENCEI-SELF-MODIFY-01`.
- `Zihintpause/`: `MCU-ZIHINTPAUSE-01`.

The `C/` and `Zifencei/` images are run in the SoC regression because they
verify delivered MCU integration. `M/`, `Zba/`, `Zbb/`, `Zbs/`, `Zicond/`, and `PMP/` are
core regressions; the B-extension tests exercise the shared integer-ALU execution
and forwarding contract directly.

### Legacy phased core tests

- `legacy/phase1/`: `P1-ALU-01`.
- `legacy/phase2/`: `P2-CFLOW-01`.
- `legacy/phase4/`: `P4-FWD-01`, `P4-LDST-01`.
- `legacy/phase5/`: `P5-CSR-TRAP-01`.
- `legacy/phase7/`: `P7-CSR-DEP-01`, `P7-CTRL-KILL-01`, `P7-FWD-STRESS-01`,
  `P7-LDST-STRESS-01`.
- `legacy/phase8/`: `P8-COUNTER-01`. `P8-HPM-01` retired; replaced by `MCU-HPM-01`.
- `legacy/phase9/`: `P9-IRQ-01`.
- `legacy/phase10/`: `P10-MEMWAIT-01`.
- `legacy/phase11/`: `P11-EBREAK-DRET-01`, `P11-EXT-HALT-01`, `P11-STEP-01`.

## `soc/tests/`

| Class | Testcases | Use |
| --- | --- | --- |
| `product` | `MCU-BUS-UNMAPPED-01`, `MCU-STORE-FAST-01`, `MCU-LMEM-LOAD-BRANCH-01`, `MCU-LMEM-LOAD-STORE-DATA-01`, `MCU-LOAD-RESPONSE-BYPASS-01`, `MCU-CLKRST-01`, `MCU-LP-WFI-TIMER-01`, `MCU-PMP-SOC-01`, `MCU-CLINT-01`, `MCU-TIME-CSR-01`, `MCU-CLINT-MSIP-IRQ-01`, `MCU-CLINT-MTIP-IRQ-01`, `MCU-PLIC-01`, `MCU-PLIC-IRQ-01`, `MCU-PLIC-PENDING-PRIORITY-01`, `MCU-PLIC-SOURCE-SWEEP-01`, `MCU-DEBUG-ABSTRACT-01`, `MCU-DEBUG-GPR-SWEEP-01`, `MCU-DEBUG-COMPLETE-01`, `MCU-DEBUG-JTAG-01`, `MCU-DEBUG-JTAG-STRESS-01`, `MCU-DEBUG-OPENOCD-LIKE-01`, `MCU-BOOT-DATA-INIT-JTAG-ELF-01` | Product-owned eRISCV-M2 evidence. `MCU-STORE-FAST-01` covers same-edge DTCM/CLINT/PLIC stores; the LMEM and response-bypass cases cover the dedicated GPR forwarding paths; JTAG-ELF replays a host-generated private-DMI boot trace. `MCU-PMP-SOC-01` covers reset-unconfigured access, locked DMEM/APB/IMEM DBus denial, IMEM fetch denial, precise traps, normal unmapped-APB error after PMP enable, and protected firmware-word integrity. |
| `legacy-adapted` | `UART-LOOPBACK-01`, `UART-HELLO-01`, `UART-ECHO-01`, `GPIO-BASIC-01`, `TIMER-POLL-01`, `SPI-BASIC-01` | Imported old-SoC collateral adapted to eRISCV-M2 agents. |

The superseded JTAG/DMI reference collateral was removed after its coverage,
including invalid-DMI error responses, was absorbed by the Debug 1.0 product
scenarios.

## `../compliance/`

After `make act-generate-m2`, `../compliance/riscv-arch-test/generated/`
contains the base and U-mode `.mem`, `.data.mem`, and `.act.json` cache used
by `--act-full`. PMPSm remains an explicit product-local generation flow. The
cache is not source-controlled.

Use `make -C eriscv-m2/dv/core/sim list` or
`make -C eriscv-m2/dv/soc/sim list` to inspect the exact runnable set in
the current checkout. When an imported testcase becomes product evidence,
update this inventory and the product verification contract in the same change.

## Contributing a Test

1. **Source**: Write an assembly source (`.S`) following the product test
   conventions (use `dv/core/tests/C/MCU-C-01.S` or `dv/core/tests/M/MCU-M-01.S` as
   a template).
2. **Build**: Compile with the product GCC toolchain to produce `.elf`, `.bin`,
   and `.mem` images. The Make flow under `dv/core/sim` or `dv/soc/sim`
   typically handles this; consult the simulation Makefile for the exact
   recipe.
3. **Oracle**: Provide an `.expected_regs` file (GPR dump oracle) and, for
   SoC tests, add any required TB agent configuration (interrupt injection,
   peripheral stimulus, debug DMI sequences).
4. **Register**: Add the testcase name to the appropriate test list in the
   simulation regression script (`dv/core/sim/run_regression.py` or
   `dv/soc/sim/run_regression.py`).
5. **Document**: Add the testcase to this inventory with purpose, execution
   flow, and oracle details.
6. **Verify**: Run the regression locally before submitting:

   ```bash
   # Core test
   make -C eriscv-m2/dv/core/sim modelsim TESTS=MY-NEW-TEST
   # SoC test
   make -C eriscv-m2/dv/soc/sim modelsim TESTS=MY-NEW-TEST
   ```
