# eRISCV-AP VCU108 integration

The AP FPGA target is the Xilinx VCU108 (`xcvu095-ffva2104-2-e`).  The
portable SoC exports a 64-bit `axi_mem` DDR boundary; board-specific RTL must
adapt that boundary to the generated DDR4 MIG.

## DDR4 source IP

`ip/mig_ddr4_0/mig_ddr4_0/mig_ddr4_0.xci` is the source-controlled Vivado
2025.2 configuration for VCU108 DDR4 C1:

- Board preset: `ddr4_sdram_c1_062`
- Device: `MT40A256M16LY-062E`, 2 GiB
- MIG user AXI: 512-bit data, 4-bit ID, 31-bit local DDR address
- Reference clock: `sysclk1_300` (300 MHz)

Run `scripts/create_mig.tcl` with Vivado only when the source XCI is absent.
When it exists, the script exits without importing it, avoiding numbered IP
siblings.  Generated IP targets, HDL, constraints, and example-design files
are build products and are intentionally not version controlled.

## AP integration status

The source XCI exists, but an AP board top does not yet.  The remaining FPGA
work is to add an `eriscv_ap_vcu108_top`, subtract `AP_DDR_BASE` from the AP's
48-bit physical address, adapt 64-bit AXI to the MIG's 512-bit AXI, and hold
SoC reset until MIG calibration completes.  Only then can synthesis, timing,
bitstream generation, and board validation be claimed.

The tracked `eriscv_m2_*` wrapper and project scripts are legacy bootstrap
material, not an eRISCV-AP build flow; they must not be used to build this
product.
