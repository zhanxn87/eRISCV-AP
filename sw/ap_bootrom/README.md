# AP first-stage boot image

`make images` builds the fixed-reset-vector Boot ROM and a tiny DDR payload
for the SoC boot-chain regression. It is independent from the legacy M2
`sw/Makefile` and targets `rv64imac_zicsr_zifencei` with `lp64`.

The BPI image consists of a 64-byte little-endian header followed by a payload
padded to an eight-byte boundary:

| Offset | Field |
|---:|---|
| `0x00` | magic: `0x4552495343564150` |
| `0x08` | format version: `1` |
| `0x10` | payload byte count |
| `0x18` | DDR load address |
| `0x20` | entry address |
| `0x28` | payload XOR64 checksum |
| `0x30..0x3f` | reserved, zero |

The first-stage ROM validates the header, verifies its non-cryptographic XOR64
payload checksum while copying via aligned 64-bit BPI reads, executes `fence.i`,
and jumps to the entry address. The
first BPI controller revision is read-only and is intentionally not a CFI,
program, or erase implementation.

```bash
make -C /home/zhanx/projects/eRISCV-AP/sw/ap_bootrom images
make -C /home/zhanx/projects/eRISCV-AP/dv/soc/sim ap-soc-flash-boot-regression
make -C /home/zhanx/projects/eRISCV-AP/dv/soc/sim ap-soc-flash-boot-sv39
```
