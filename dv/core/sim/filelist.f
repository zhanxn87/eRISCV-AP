// eRISCV-AP RV64 regression source manifest.
// Expand this hierarchy before invoking a simulator:
//   python3 ../../../../tools/project/resolve_filelist.py filelist.f --output file.list

-f ../../../rtl/riscv_core/filelist.f

../../../rtl/soc/mem/sram_1rw.sv
../../../rtl/soc/mem/instr_mem.sv
../../../rtl/soc/mem/data_mem.sv
../../../rtl/soc/axi/cache_axi4_line_adapter.sv
../../../rtl/soc/cache/dcache.sv
../tb/axi4_line_mem.sv
../tb/clint_plic_mmio.sv
../tb/riscv_wrapper.sv
../tb/riscv_tb.sv
../tb/fpu_adapter_tb.sv
