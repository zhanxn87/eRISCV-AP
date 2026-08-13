/*
 * eRISCV-MCU SoC initialization
 * Copyright (c) 2024 eRISCV-MCU Contributors
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/init.h>
#include <zephyr/arch/cpu.h>
#include <zephyr/sys/sys_io.h>
#include <soc.h>

/* CLINT and PLIC base addresses — must match hardware */
#define ERISCV_MCU_CLINT_BASE  0x02000000u
#define ERISCV_MCU_PLIC_BASE   0x0c000000u
#define ERISCV_MCU_MTIME_OFF   0xbff8u
#define ERISCV_MCU_MTIMECMP_OFF 0x4000u
#define ERISCV_MCU_MSIP_OFF    0x0000u

/**
 * @brief Early SoC initialization, runs before kernel start.
 */
static int eriscv_mcu_soc_init(void)
{
	if (IS_ENABLED(CONFIG_ERISCV_MCU_WFI_CLOCK_GATING)) {
		sys_write32(ERISCV_MCU_CLKRST_WFI_SLEEP_EN,
			    ERISCV_MCU_CLK_RST_BASE + ERISCV_MCU_CLKRST_SLEEP_CTRL);
	}
	return 0;
}

SYS_INIT(eriscv_mcu_soc_init, PRE_KERNEL_1, 0);
