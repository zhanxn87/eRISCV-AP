// eriscv-m2 soc RTL filelist — synthesis / lint target.
// Top: soc
// Includes core filelist via -f

// --- core (nested filelist) ---
-f ../riscv_core/filelist.f

// --- shared APB peripherals (nested; resolver expands this for tools) ---
-f ../../../peripherals/uart/filelist.f
-f ../../../peripherals/gpio/filelist.f
-f ../../../peripherals/timer/filelist.f
-f ../../../peripherals/spi/filelist.f
-f ../../../peripherals/clk_rst/filelist.f

// --- soc infrastructure ---
soc_pkg.sv
bus/ibus48_to_ibus32_adapter.sv
bus/dbus64_to_dbus32_adapter.sv
bus/dbus_interconnect.sv
bus/dbus_to_apb.sv
bus/apb_interconnect.sv
mem/sram_1rw.sv
mem/instr_mem.sv
mem/data_mem.sv
mem/data_mem_arbiter.sv
mem/lmem64_to_lmem32_adapter.sv
mem/system_sram.sv
mem/system_sram_arbiter.sv
mem/system_sram_fabric.sv
dma/dma_controller.sv
plic.sv
clint.sv
debug/debug_module_min.sv
debug/sba_dmi.sv
debug/jtag_dtm.sv
debug/dmi_cdc.sv
debug/jtag_debug_subsystem.sv
debug/dmi_mm_bridge.sv
boot/boot_source_arbiter.sv
boot/boot_uart_rx.sv
boot/dmi_boot_slave.sv
boot/imem_boot_ctrl.sv
boot/uart_boot_slave.sv
boot/boot_subsystem.sv
sys_ctrl.sv
reset_sync.sv
clock_gate.sv
soc.sv
-f ../../../peripherals/watchdog/filelist.f
