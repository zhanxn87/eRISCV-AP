# eRISCV-M2 ACT4 Profile

This is the sole architectural-test flow for eRISCV-M2 MCU verification. The
base profile selects `I`, `M`, `F`, `Zca`, `Zcf`, `Zicsr`, `Zifencei`, `Zicntr`, `Zihpm`, `Zihintpause`, standard B (`Zba`, `Zbb`, `Zbs`), and `Zicond`. A fresh corpus includes the generated F/Zcf artifacts and the M2-local `Zihpm` pair. The current upstream ACT selection produces no B artifact; `MCU-ZBA-01`, `MCU-ZBB-01`, `MCU-ZBS-01`, and `MCU-ZICOND-01` provide product-directed extension evidence.
`build_u.sh` adds the U-mode, PMPU/MPRV, and `ZicntrU` selection (12
artifacts). UDB represents the RV32C base through `Zca`.

The ACT4 reference map models the core-TB contiguous 512 KiB test image range (`0x0000_0000..0x0007_ffff`): the executable image occupies the first 256 KiB and linker data/signatures may use the second 256 KiB. This accommodates the full generated RV32F signature corpus.

ACT4 artifacts are local, reproducible cache under:

```text
eriscv-m2/compliance/riscv-arch-test/generated/
```

The cache contains instruction `.mem`, optional `.data.mem`, and `.act.json`
manifests. It is ignored by Git. The pinned `riscv-arch-test` submodule remains
the source of the ACT assembly.

ACT4 build work is kept in `work/` and `work-pmp/`; shared tool caches are kept in `.cache/act4/`. Both locations are ignored by Git.

Rebuild the cache when needed:

```bash
make act-generate-m2
```

Set up the required ACT4 tools first using the repository-level
[ACT4 instructions](../../../README.md#generate-act4-artifacts-optional).
Native hosts use `make ACT_BOOTSTRAP_ARGS=--all act-bootstrap-native` once,
then this target. `make act-generate-m2-container` is the Docker fallback.

## PMP subset

`build_pmp.sh` generates only ACT4's M-mode PMP family (`PMPSm`) using the
16-entry, 4-byte-granularity product declaration. It does not select S-mode,
U-mode, virtual-memory, atomics, cache-block, or Smepmp-dependent PMP tests.
The UDB `Sm` marker models M-mode privileged behavior only; it does not expand
the eRISCV-M2 product contract. `pmpsm_cfg_A_tor_zero` is excluded because
its Sail reference run jumps to unmapped address zero, a platform assumption
outside this MCU memory map.

The core TB supports DBUS reads and byte writes only in its executable IMEM
window (`0x0000_0000..0x0003_ffff`). PMPSm payloads outside that window need a
SoC executable-memory map or an explicitly compatible core harness. They are
not product unified-memory evidence and are excluded from the default core-TB
selection.

```bash
eriscv-m2/compliance/riscv-arch-test/build_pmp.sh
```

## U-mode subset

`build_u.sh` imports ACT4's U-mode, U-mode exception/interrupt, PMPU, and
`ZicntrU` tests into the shared generated corpus. The profile includes the
MPRV PMPU checks and counter-delegation tests; Sail and UDB declare the same
seven writable `mcounteren` bits (CY, TM, IR, and HPM3..6).

Payload-executing PMPU tests declare `exec_data_mirror` in their generated
manifests so the core-only split-memory TB mirrors only their writable execution
payload into IMEM. Dated results are in the
[MCU Evidence Snapshot](../../../docs/Verification/eriscv-mcu-simulation-evidence-snapshot.md).

```bash
eriscv-m2/compliance/riscv-arch-test/build_u.sh
```
