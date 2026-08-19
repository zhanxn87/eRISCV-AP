# eRISCV-AP VCU108 integration

The AP FPGA target is the Xilinx VCU108 (`xcvu095-ffva2104-2-e`). The board
project top is `rtl/eriscv_ap_vcu108_top.sv`; it replaces the removed M2
wrapper. Build it on Windows with:

```powershell
cd <repo>\fpga\vcu108
.\run_vivado.ps1 -Flow gui
.\run_vivado.ps1 -Flow synth
.\run_vivado.ps1 -Flow impl
```

`run_vivado.ps1` locates Windows Vivado. The WSL-visible launcher in this
workspace is not a Linux Vivado executable, so WSL cannot run the flow itself.

## Board composition

- `ap_soc` runs at 50 MHz from MIG auxiliary UI clock output 1. An AXI CDC
  crosses its 64-bit DDR port into the calibrated 300 MHz MIG UI domain, where
  `ap_axi_ddr_bridge` rebases the 48-bit AP DDR aperture and converts to the
  checked-in MIG's 31-bit-address, 512-bit AXI port. SoC reset remains
  asserted until MIG calibration completes.
- The BPI aperture leaves portable RTL as a 48-bit/64-bit AXI4 target. The
  board `ap_axi_bpi_bridge` filters ATOP, rebases to the local 32-bit aperture,
  and crosses to the AXI EMC 100 MHz clock. `axi_emc_bpi` is the checked-in
  VCU108 x16 NOR configuration; `ap_vcu108_bpi_io` connects its data[3:0],
  CE#, and 50 MHz CCLK through `STARTUPE3`, and data[15:4] through IOBUFs.
- `gig_ethernet_pcs_pma_0` implements the M88E1111 SGMII-over-LVDS PHY path.
  Its `sgmii_clk_en` reaches the AP GMII MAC, so 10/100M rate enables are not
  hard-wired as gigabit-only behavior.

MIG and AXI EMC source XCIs are copied into `build/ip/` before target
generation. The project declares `xilinx.com:vcu108:part0:1.7`, allowing MIG's
generated board constraints to resolve the DDR4 interface to VCU108 package
pins and timing. PCS/PMA is generated directly under `build/ip/`. Generated
HDL, IP products, reports, and bitstreams are intentionally untracked.

## Constraints and boot media

`constraints/vcu108.xdc` contains the AP console, LEDs, SGMII, BPI ordinary
I/O, board clocks, and master-BPI configuration properties. Dedicated BPI
configuration pins are deliberately absent from top-level constraints because
`STARTUPE3` owns them. The BPI timing values match the VCU108
MT28GU01GAAA1EGC reference design (96 ns maximum address/CE-to-data access).

The ROM image and FPGA configuration bitstream are separate flash contents:
BPI configuration starts at flash offset 0; the AP boot ROM reads its software
image from the AP BPI memory-map aperture. Packaging/programming those two
images and proving timing closure/board boot are implementation-flow and
hardware-validation steps, not covered by RTL simulation.

## Verification status

The portable `ap-soc-flash-boot` regression proves Boot ROM -> simulated BPI
NOR -> DDR -> payload execution. `check-filelist` validates the 232-source AP
simulation manifest. Vivado elaboration, synthesis, routed timing, bitstream
creation, and VCU108 hardware bring-up remain unverified in this environment:
the available WSL launcher lacks its Linux Vivado executable. Run the Windows
commands above before treating the board target as released.
