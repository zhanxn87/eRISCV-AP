// eRISCV-AP SoC RTL filelist.
// Top: ap_soc

// AP architecture packages and frozen PULP AXI implementation.
ap_soc_pkg.sv

// The complete private RV64GC hart implementation.
-f hart_tile/filelist.f

// Shared AP architecture and local integration logic.
boot/ap_boot_rom.sv
-f memory/filelist.f
-f peripherals/filelist.f
-f ethernet/filelist.f
ap_cluster.sv
ap_soc.sv
