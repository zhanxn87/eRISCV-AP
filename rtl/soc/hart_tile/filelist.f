// AP hart-tile RTL manifest. ap_hart_tile is the reusable SoC/cluster unit.
// The execution pipeline remains an implementation submodule under core/.
-f core/filelist.f
-f ../../vendor/axi/filelist.f
mem/cache/icache.sv
mem/cache/dcache.sv
mem/cache/dcache_cpu_router.sv
mem/axi/cache_axi4_line_adapter.sv
mem/axi/ap_uncached_axi_master.sv
mem/ap_hart_memory_frontend.sv
ap_hart_tile.sv
