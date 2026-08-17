// eRISCV-AP SoC verification source manifest.
// Expand with:
//   python3 ../../../tools/project/resolve_filelist.py filelist.f --output file.list

+incdir+../../hart_tile/tb
+incdir+../tb

-f ../../../rtl/soc/filelist.f
../../hart_tile/tb/axi4_line_mem.sv
../tb/ap_bpi_nor_model.sv
../tb/ap_soc_elab_tb.sv
../tb/ap_soc_flash_boot_tb.sv
../tb/ap_soc_flash_boot_extended_tb.sv
../tb/ap_soc_flash_boot_sv39_tb.sv
../tb/ap_soc_periph_route_tb.sv
../tb/ap_peripheral_subsystem_tb.sv
../tb/ap_soc_sv39_route_tb.sv
../tb/ap_soc_sv39_fault_tb.sv
../tb/ap_soc_debug_route_tb.sv
../tb/ap_ethernet_dma_tb.sv
