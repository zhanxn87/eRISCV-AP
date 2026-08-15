// eRISCV-AP SoC verification source manifest.
// Expand with:
//   python3 ../../../tools/project/resolve_filelist.py filelist.f --output file.list

+incdir+../../core/tb
+incdir+../tb

-f ../../../rtl/soc/filelist.f
../../core/tb/axi4_line_mem.sv
../tb/ap_soc_elab_tb.sv
../tb/ap_soc_periph_route_tb.sv
../tb/ap_peripheral_subsystem_tb.sv
../tb/ap_soc_sv39_route_tb.sv
../tb/ap_soc_sv39_fault_tb.sv
../tb/ap_soc_debug_route_tb.sv
