# eRISCV-MCU SoC CMake
# Copyright (c) 2024 eRISCV-MCU Contributors
# SPDX-License-Identifier: Apache-2.0

if(CONFIG_SOC_ERISCV_MCU)

zephyr_include_directories(${ZEPHYR_BASE}/include)
zephyr_sources(
  soc.c
  drivers/uart.c
  ${ZEPHYR_BASE}/soc/riscv/common/riscv-privileged/soc_irq.S
  ${ZEPHYR_BASE}/soc/riscv/common/riscv-privileged/soc_common_irq.c
  ${ZEPHYR_BASE}/soc/riscv/common/riscv-privileged/vector.S
)

zephyr_sources_ifdef(CONFIG_ERISCV_UART_IRQ_CONSOLE console/uart_irq_console.c)
zephyr_sources_ifdef(CONFIG_GPIO_ERISCV drivers/gpio.c)
zephyr_sources_ifdef(CONFIG_COUNTER_ERISCV drivers/timer.c)
zephyr_sources_ifdef(CONFIG_WDT_ERISCV drivers/wdt.c)
zephyr_sources_ifdef(CONFIG_SPI_ERISCV drivers/spi.c)

# Use custom linker script matching eRISCV-MCU memory map
set(SOC_LINKER_SCRIPT ${CMAKE_CURRENT_SOURCE_DIR}/linker.ld CACHE INTERNAL "")

endif()
