# M2 CVFPU Vendor Lock

This directory is an immutable source snapshot for eRISCV-M2. It is unpacked
from the revisions below without nested Git metadata. Builds use M2-local file
lists only; no dependency resolver or network fetch is permitted.

| Component | Local directory | Upstream | Revision | Snapshot files | Snapshot tree SHA-256 | License record |
| --- | --- | --- | --- | ---: | --- | --- |
| CVFPU / FPnew | `cvfpu` | `https://github.com/pulp-platform/cvfpu.git` | `841b19b9fc0148ee7cbf91c295e801c6bf21a421` | 89 | `106c9bf1e7eff4e926faa65e53ae8ed2b1d2d5a78b33a14c8076c34f470b044b` | source headers and `Bender.yml`: SHL-0.51; repository carries `LICENSE.solderpad` and `LICENSE.apache` |
| common_cells | `../common_cells` | `https://github.com/pulp-platform/common_cells.git` | `v1.21.0` / `6aeee85d0a34fedc06c14f04fd6363c9f7b4eeea` | 132 | `e96ba65d3a58ed2ac7e178e67e8a5d1a0b7cb5bbb778edabd6d1344b2e6cd256` | `LICENSE`: SHL-0.51, with an Apache-2.0 option granted to licensees |
| fpu_div_sqrt_mvp | `../fpu_div_sqrt_mvp` | `https://github.com/pulp-platform/fpu_div_sqrt_mvp.git` | `v1.0.4` / `86e1f558b3c95e91577c41b2fc452c86b04e85ac` | 14 | `de377f0b7413c98da8907a1924116122df510f3e9a73df50ac4488770647585a` | `LICENSE`: SHL-0.51, with an Apache-2.0 option granted to licensees |

The tree hash is `sha256sum` over the sorted per-file `sha256sum` manifest,
including relative snapshot paths. It excludes this `LOCK.md`, which is an M2
local record rather than upstream source.

## M2-local correctness patch

`src/fpnew_fma.sv` extends FMA underflow detection beyond a final packed
subnormal result to cover the directed-rounding min-normal boundary. `UF` remains
qualified by `NX`; the boundary term applies only when a maximal subnormal with a
clear guard bit rounds into minimum normal. This is an M2-local delta to
the locked upstream revision; the table hash remains the unmodified source
snapshot baseline.

## Selected product contract

- Features: `fpnew_pkg::RV32F` only (IEEE binary32, RV32 integer conversion,
  no D, vectors, PACE, or custom/transprecision formats).
- M2 selects `DEFAULT_SNITCH_PIPE` and the FP32-only `TH32` divider/square-root through
  the product-local adapter. `DEFAULT_NOREGS` is prohibited. Timing closure must
  still measure this selected configuration.
- `Bender.yml` declares `common_cells` v1.21.0 and `fpu_div_sqrt_mvp` v1.0.4.
  Their M2-local snapshots above satisfy those dependencies. `common_cells`
  also declares verification/technology packages, but M2's selected synthesis
  source manifest must not import them unless a selected source requires them.
