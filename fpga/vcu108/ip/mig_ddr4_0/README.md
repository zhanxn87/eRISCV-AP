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

Only `mig_ddr4_0/mig_ddr4_0.xci` is source-controlled.  `scripts/project_vcu108.tcl` copies it into `build/ip/` before target generation, so HDL, constraints, simulation sources, and example-design products stay build-local.

The portable AP SoC remains 64-bit AXI. `rtl/ap_axi_ddr_bridge.sv` rebases the AP DDR aperture, filters unsupported AXI atomics, and converts 64-bit AXI to the MIG's 512-bit user AXI.
