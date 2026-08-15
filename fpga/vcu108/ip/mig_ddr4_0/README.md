# VCU108 C1 DDR4 MIG

`../../scripts/create_mig.tcl` creates this source XCI with Vivado 2025.2 when
it is absent.  If the XCI already exists, the script exits without importing it
into an in-memory project; this prevents Vivado from creating numbered sibling
IP directories.

- Board preset: `ddr4_sdram_c1_062`
- DDR4 part: `MT40A256M16LY-062E`
- Capacity: 2 GiB (`C0.DDR4_AxiAddressWidth = 31`)
- MIG user AXI: 512-bit data, 4-bit ID
- Reference clock: VCU108 `sysclk1_300` (300 MHz)

Only `mig_ddr4_0/mig_ddr4_0.xci` is source-controlled.  A future AP board
project consumes it and produces generated HDL, constraints, simulation
sources, and example-design products in its build directory.

The portable AP SoC remains 64-bit AXI.  The board wrapper must rebase the AP
DDR aperture and convert 64-bit AXI to the MIG's 512-bit user AXI before this
IP.
