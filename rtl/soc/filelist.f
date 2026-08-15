// eRISCV-AP SoC RTL filelist.
// Top: soc

// RV64GC hart and frozen PULP AXI implementation.
-f ../riscv_core/filelist.f
-f ../vendor/axi/filelist.f

// AP architecture and local integration logic.
ap_soc_pkg.sv
boot/ap_boot_rom.sv
cache/icache.sv
cache/dcache.sv
cache/dcache_cpu_router.sv
mem/ap_hart_memory_frontend.sv
axi/cache_axi4_line_adapter.sv
axi/ap_uncached_axi_master.sv
axi/ap_axi64_idle_master.sv
axi/ap_axi64_egress_bridge.sv
axi/ap_axi64_error_slave.sv
axi/ap_axi64_fabric.sv
axi/ap_axi64_peripheral_router.sv
axi/ap_axi64_to_dbus32.sv
clint.sv
plic.sv
ap_apb_interconnect.sv
-f ../peripherals/uart/filelist.f
-f ../peripherals/gpio/filelist.f
-f ../peripherals/timer/filelist.f
-f ../peripherals/spi/filelist.f
ap_hart_tile.sv
ap_cluster.sv
ap_ethernet_subsystem.sv
ap_memory_system.sv
ap_peripheral_subsystem.sv
soc.sv
