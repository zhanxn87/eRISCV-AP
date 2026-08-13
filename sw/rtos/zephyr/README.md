# eRISCV-M2 Zephyr Port

Zephyr RTOS v3.6 LTS board and SoC port for the eRISCV-M2 educational RISC-V MCU.

## Prerequisites

```bash
# Init Zephyr submodule (first time only)
cd edu-mcu
git submodule update --init third_party/zephyr
cd third_party/zephyr
pip3 install west
west init -l .
west update

# Install Zephyr SDK (cross-compiler)
wget https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.16.5/zephyr-sdk-0.16.5_linux-x86_64.tar.xz
tar xf zephyr-sdk-0.16.5_linux-x86_64.tar.xz -C /opt

# Set SDK path
export ZEPHYR_SDK=/opt/zephyr-sdk
```

## Build

```bash
# Set environment
export ZEPHYR_BASE=/opt/zephyrproject/zephyr
export ZEPHYR_SDK=/opt/zephyr-sdk

# Build from M2 sw directory
make -C eriscv-m2/sw zephyr

# Or build directly with cmake
cd eriscv-m2/sw/rtos/zephyr
make images
```

## Run Simulation

```bash
make -C eriscv-m2/sw sim-zephyr
```

## Board Configuration

| Parameter | Value |
|---|---|
| Board | `eriscv_mcu` |
| SoC | `eriscv_mcu` |
| Hardware ISA | RV32IMFC + Zicsr/Zifencei/Zicntr/Zihpm/Zihintpause/Zba/Zbb/Zbs/Zicond/Zcf |
| RTOS ISA | RV32IMC + Zicsr/Zifencei/Zicntr/Zihpm/Zihintpause/Zba/Zbb/Zbs/Zicond (no F task context) |
| M-mode | Yes (machine timer via CLINT) |
| U-mode + PMP | 16-entry PMP, available but not exercised by default |
| ITCM (FLASH) | 128 KB at 0x10000000 |
| DTCM (SRAM) | 128 KB at 0x11000000 |
| System SRAM | 512 KB at 0x80000000 (available to applications; not Zephyr default RAM) |
| System Clock | 100 MHz |
| Tick Rate | 1000 Hz |
| PLIC | 32 sources |
| UART | 1 (early polling console; interrupt-driven TX console) |

## Features Enabled

- Multi-threading (cooperative + preemptive)
- Semaphore synchronization
- printk console output via UART
- Machine timer via CLINT

## Memory Budget

| Region | Size | Usage |
|---|---|---|
| Main thread stack | 4096 B | kernel main thread |
| Thread A stack | 1024 B | demo thread |
| Thread B stack | 1024 B | demo thread |
| Idle stack | 1024 B | kernel idle |
| ISR stack | 4096 B | interrupt handlers |
| Kernel objects | ~4 KB | semaphores, thread metadata |

Total DTCM footprint: ~14 KB (of 128 KB available).

## Limitations

- No MMU or S-mode support; supervisor-mode Zephyr features disabled.
- Early startup uses the standard polling hook. After kernel startup, `printk`
  TX uses a 256-byte ring buffer drained by UART/PLIC source 1 interrupts.
- No filesystem, networking, or USB support.
- No dynamic memory allocation (heap) — `CONFIG_HEAP_MEM_POOL_SIZE=0`.
- PMP is present in hardware but Zephyr PMP/MPU stack guards are not configured.
- This port is a development-grade smoke test, not a production Zephyr BSP.
