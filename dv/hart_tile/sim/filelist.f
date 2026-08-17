// eRISCV-AP hart-tile regression source manifest.
// Expand this hierarchy before invoking a simulator:
//   python3 ../../../../tools/project/resolve_filelist.py filelist.f --output file.list

../../../rtl/soc/ap_soc_pkg.sv
-f ../../../rtl/soc/hart_tile/filelist.f

../tb/models/sram_1rw.sv
../tb/models/instr_mem.sv
../tb/models/data_mem.sv
../../../rtl/soc/boot/ap_boot_rom.sv
../tb/axi4_line_mem.sv
../tb/axi4_line_mem_tb.sv
../tb/ap_hart_tile_smoke_tb.sv
../tb/clint_plic_mmio.sv
../tb/riscv_wrapper.sv
../tb/riscv_tb.sv
../tb/sfence_vma_metadata_tb.sv
../tb/zicbom_metadata_tb.sv
../tb/fpu_adapter_tb.sv
