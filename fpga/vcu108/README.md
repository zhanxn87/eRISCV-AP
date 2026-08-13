# eRISCV-M2 VCU108 Vivado Project

Independent VCU108 project for the M2 product (`RV32IMFC_Zicsr_Zifencei_Zicntr_Zihpm_Zihintpause_Zba_Zbb_Zbs_Zcf` plus PMP). It resolves
the product-local `rtl/soc/filelist.f` at project-creation time, so an M2 RTL
change is picked up without copying a source list from M0.

## Target

- Board: Xilinx VCU108 (`xcvu095-ffva2104-2-e`)
- Top: `eriscv_m2_vcu108_wrapper`
- SoC clock: 100 MHz, generated from `sysclk1_300`
- Debug: Debug 1.0 DTM through `BSCANE2` JTAG chain 2
- Timing: latest routed report misses 100 MHz by 0.050 ns (WNS -0.050 ns, TNS -0.838 ns, 37 setup failing endpoints)

The wrapper connects the USB UART and boot-mode DIP switches. GPIO, SPI MISO,
and external PLIC IRQ inputs are tied inactive until a specific expansion
connector is selected. The two user LEDs report UART boot overrun and protocol
error. The on-chip SRAM has no fixed FPGA image: use boot mode 1 (JTAG DMI) or
2 (UART) to load IMEM; mode 0 only bypasses the boot loader. UART boot is
one-shot: `RELEASE` hands the shared RX pin to runtime UART until the next
reset, so terminal bytes cannot be interpreted as boot commands.

## Run from Windows PowerShell

```powershell
# From the repository root:
cd .\eriscv-m2\fpga\vcu108
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run_vivado.ps1 -Flow gui
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run_vivado.ps1 -Flow synth
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run_vivado.ps1 -Flow impl
```

The command uses a process-local `Bypass` policy and does not change the
machine or user execution policy. `run_vivado.cmd -Flow gui` is an equivalent
unsigned-script-safe entry point.

`synth` writes utilization, timing, and clock reports under `build/`. `impl`
stops after routed implementation and writes DRC/methodology reports and a DCP;
bitstream generation and board validation remain P14 work.
