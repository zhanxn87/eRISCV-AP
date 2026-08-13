/* SPDX-FileCopyrightText: 2025-2026 Xianning Zhan */
/* SPDX-License-Identifier: BSD-3-Clause */

#ifndef ERISCV_MCU_H
#define ERISCV_MCU_H

/**
 * @file eriscv_mcu.h
 * @brief Stable v0.1.0 bare-metal BSP API for eRISCV-MCU.
 *
 * The selected product supplies eriscv_mcu_config.h. All addresses are 32-bit
 * MMIO addresses and all APIs execute in M-mode.
 */
#include "eriscv_mcu_config.h"
typedef unsigned char      eriscv_mcu_u8;
typedef unsigned int       eriscv_mcu_u32;
typedef unsigned long long eriscv_mcu_u64;

#define ERISCV_MCU_BSP_VERSION_MAJOR 0u
#define ERISCV_MCU_BSP_VERSION_MINOR 1u
#define ERISCV_MCU_BSP_VERSION_PATCH 0u
#define ERISCV_MCU_BSP_VERSION_STRING "0.1.0"

#define ERISCV_MCU_CLINT_MSIP      0x0000u
#define ERISCV_MCU_CLINT_MTIMECMP  0x4000u
#define ERISCV_MCU_CLINT_MTIME     0xbff8u

#define ERISCV_MCU_PLIC_PRIORITY(id) (4u * (eriscv_mcu_u32)(id))
#define ERISCV_MCU_PLIC_PENDING      0x1000u
#define ERISCV_MCU_PLIC_ENABLE       0x2000u
#define ERISCV_MCU_PLIC_THRESHOLD    0x200000u
#define ERISCV_MCU_PLIC_CLAIM        0x200004u

#define ERISCV_MCU_UART_TXDATA      0x00u
#define ERISCV_MCU_UART_RXDATA      0x04u
#define ERISCV_MCU_UART_STATUS      0x08u
#define ERISCV_MCU_UART_BAUDDIV     0x0cu
#define ERISCV_MCU_UART_CTRL        0x10u
#define ERISCV_MCU_UART_TX_WATERMARK 0x14u
#define ERISCV_MCU_UART_RX_WATERMARK 0x18u
#define ERISCV_MCU_UART_IRQ_STATUS  0x1cu
#define ERISCV_MCU_UART_STATUS_TX_READY (1u << 0)
#define ERISCV_MCU_UART_STATUS_RX_VALID (1u << 1)
#define ERISCV_MCU_UART_STATUS_TX_BUSY  (1u << 2)
#define ERISCV_MCU_UART_STATUS_RX_OVERRUN (1u << 3)
#define ERISCV_MCU_UART_CTRL_TX_ENABLE  (1u << 0)
#define ERISCV_MCU_UART_CTRL_RX_ENABLE  (1u << 1)
#define ERISCV_MCU_UART_CTRL_RX_IRQ_EN  (1u << 2)
#define ERISCV_MCU_UART_CTRL_TX_IRQ_EN  (1u << 3)
#define ERISCV_MCU_UART_CTRL_ERR_IRQ_EN (1u << 4)
#define ERISCV_MCU_UART_IRQ_RX_WATERMARK (1u << 0)
#define ERISCV_MCU_UART_IRQ_TX_WATERMARK (1u << 1)
#define ERISCV_MCU_UART_IRQ_RX_OVERRUN   (1u << 2)
#define ERISCV_MCU_GPIO_OUT         0x00u
#define ERISCV_MCU_GPIO_IN          0x04u
#define ERISCV_MCU_GPIO_DIR         0x08u

#define ERISCV_MCU_TIMER_CTRL       0x00u
#define ERISCV_MCU_TIMER_COUNT      0x04u
#define ERISCV_MCU_TIMER_COMPARE    0x08u
#define ERISCV_MCU_TIMER_STATUS     0x0cu
#define ERISCV_MCU_TIMER_CTRL_ENABLE (1u << 0)
#define ERISCV_MCU_TIMER_CTRL_IRQ_EN (1u << 1)

#define ERISCV_MCU_DMA_CTRL          0x00u
#define ERISCV_MCU_DMA_STATUS        0x04u
#define ERISCV_MCU_DMA_SRC           0x08u
#define ERISCV_MCU_DMA_DST           0x0cu
#define ERISCV_MCU_DMA_LEN           0x10u
#define ERISCV_MCU_DMA_DESC_HEAD     0x14u
#define ERISCV_MCU_DMA_CTRL_START    (1u << 0)
#define ERISCV_MCU_DMA_CTRL_IRQ_EN   (1u << 1)
#define ERISCV_MCU_DMA_CTRL_ABORT    (1u << 2)
#define ERISCV_MCU_DMA_CTRL_DESC_START (1u << 3)
#define ERISCV_MCU_DMA_CTRL_UART_TX    (1u << 4)
#define ERISCV_MCU_DMA_STATUS_BUSY   (1u << 0)
#define ERISCV_MCU_DMA_STATUS_DONE   (1u << 1)
#define ERISCV_MCU_DMA_STATUS_ERROR  (1u << 2)
#define ERISCV_MCU_DMA_STATUS_DESC_IRQ (1u << 3)

#define ERISCV_MCU_DMA_OK        0
#define ERISCV_MCU_DMA_EINVAL   -1
#define ERISCV_MCU_DMA_EBUSY    -2
#define ERISCV_MCU_DMA_EIO      -3
#define ERISCV_MCU_DMA_ETIMEOUT -4

#define ERISCV_MCU_DMA_DESCRIPTOR_ALIGN 32u
#define ERISCV_MCU_DMA_DESCRIPTOR_SIZE  32u
#define ERISCV_MCU_DMA_MAX_DESCRIPTOR_COUNT 256u
#define ERISCV_MCU_DMA_DESC_CTRL_OWN       (1u << 0)
#define ERISCV_MCU_DMA_DESC_CTRL_IRQ_EN    (1u << 1)
#define ERISCV_MCU_DMA_DESC_CTRL_END        (1u << 2)
#define ERISCV_MCU_DMA_DESC_CTRL_SRC_INC    (1u << 3)
#define ERISCV_MCU_DMA_DESC_CTRL_DST_INC    (1u << 4)
#define ERISCV_MCU_DMA_DESC_STATUS_DONE     (1u << 0)
#define ERISCV_MCU_DMA_DESC_STATUS_ERROR    (1u << 1)

typedef struct {
  eriscv_mcu_u32 next;
  eriscv_mcu_u32 source;
  eriscv_mcu_u32 destination;
  eriscv_mcu_u32 length;
  eriscv_mcu_u32 control;
  eriscv_mcu_u32 status;
  eriscv_mcu_u32 bytes_transferred;
  eriscv_mcu_u32 reserved;
} eriscv_mcu_dma_descriptor_t;

typedef char eriscv_mcu_dma_descriptor_size_must_be_32[
    sizeof(eriscv_mcu_dma_descriptor_t) == ERISCV_MCU_DMA_DESCRIPTOR_SIZE ? 1 : -1];

/* Place an uninitialized CPU/DMA-shared object in System SRAM. */
#define ERISCV_MCU_SYSTEM_SRAM_BUFFER \
  __attribute__((section(".system_sram"), aligned(4)))
#define ERISCV_MCU_DMA_DESCRIPTOR \
  __attribute__((section(".system_sram"), aligned(ERISCV_MCU_DMA_DESCRIPTOR_ALIGN)))

#define ERISCV_MCU_MIE_MSIE         (1u << 3)
#define ERISCV_MCU_MIE_MTIE         (1u << 7)
#define ERISCV_MCU_MIE_MEIE         (1u << 11)
#define ERISCV_MCU_MSTATUS_MIE      (1u << 3)
#define ERISCV_MCU_MSTATUS_FS_SHIFT 13u
#define ERISCV_MCU_MSTATUS_FS_MASK  (3u << ERISCV_MCU_MSTATUS_FS_SHIFT)
#define ERISCV_MCU_MSTATUS_FS_INITIAL (1u << ERISCV_MCU_MSTATUS_FS_SHIFT)
#define ERISCV_MCU_MSTATUS_FS_DIRTY   (3u << ERISCV_MCU_MSTATUS_FS_SHIFT)

#define ERISCV_MCU_FFLAGS_NX        (1u << 0)
#define ERISCV_MCU_FFLAGS_UF        (1u << 1)
#define ERISCV_MCU_FFLAGS_OF        (1u << 2)
#define ERISCV_MCU_FFLAGS_DZ        (1u << 3)
#define ERISCV_MCU_FFLAGS_NV        (1u << 4)

/** @brief Enable RV32F architectural state. Reset leaves mstatus.FS Off. */
static inline void eriscv_mcu_fp_enable(void) {
  __asm__ volatile ("csrs mstatus, %0" ::
                    "r"(ERISCV_MCU_MSTATUS_FS_INITIAL) : "memory");
}

/** @brief Return the architectural mstatus value, including FS. */
static inline eriscv_mcu_u32 eriscv_mcu_fp_read_mstatus(void) {
  eriscv_mcu_u32 value;
  __asm__ volatile ("csrr %0, mstatus" : "=r"(value));
  return value;
}

/** @brief Return accrued IEEE-754 exception flags. */
static inline eriscv_mcu_u32 eriscv_mcu_fp_read_fflags(void) {
  eriscv_mcu_u32 value;
  __asm__ volatile ("csrr %0, fflags" : "=r"(value));
  return value;
}

/** @brief Clear accrued IEEE-754 exception flags without changing frm. */
static inline void eriscv_mcu_fp_clear_fflags(void) {
  __asm__ volatile ("csrw fflags, zero" ::: "memory");
}

/** @brief Read the combined dynamic rounding-mode and exception CSR. */
static inline eriscv_mcu_u32 eriscv_mcu_fp_read_fcsr(void) {
  eriscv_mcu_u32 value;
  __asm__ volatile ("csrr %0, fcsr" : "=r"(value));
  return value;
}

/** @brief Set frm (bits 7:5) and fflags (bits 4:0). */
static inline void eriscv_mcu_fp_write_fcsr(eriscv_mcu_u32 value) {
  __asm__ volatile ("csrw fcsr, %0" :: "r"(value) : "memory");
}

#define ERISCV_MCU_MCAUSE_INTERRUPT (1u << 31)
#define ERISCV_MCU_MCAUSE_CODE_MASK 0x7fffffffu
#define ERISCV_MCU_MCAUSE_MSI       3u
#define ERISCV_MCU_MCAUSE_MTI       7u
#define ERISCV_MCU_MCAUSE_MEI       11u

/** @brief Write one aligned 32-bit MMIO word. */
static inline void eriscv_mcu_mmio_write32(eriscv_mcu_u32 addr, eriscv_mcu_u32 value) {
  *(volatile eriscv_mcu_u32 *)addr = value;
}

/** @brief Read one aligned 32-bit MMIO word. */
static inline eriscv_mcu_u32 eriscv_mcu_mmio_read32(eriscv_mcu_u32 addr) {
  return *(volatile const eriscv_mcu_u32 *)addr;
}

/** @brief Enable selected machine interrupt sources and global MIE. */
static inline void eriscv_mcu_enable_machine_irqs(eriscv_mcu_u32 mask) {
  __asm__ volatile ("csrs mie, %0" :: "r"(mask));
  __asm__ volatile ("csrs mstatus, %0" :: "r"(ERISCV_MCU_MSTATUS_MIE));
}

/** @brief Disable global machine interrupts. */
static inline void eriscv_mcu_disable_machine_irqs(void) {
  __asm__ volatile ("csrc mstatus, %0" :: "r"(ERISCV_MCU_MSTATUS_MIE));
}

/** @brief Assert or clear the local CLINT software interrupt. */
static inline void eriscv_mcu_clint_set_msip(int pending) {
  eriscv_mcu_mmio_write32(ERISCV_MCU_CLINT_BASE + ERISCV_MCU_CLINT_MSIP, pending ? 1u : 0u);
}

/** @brief Set the 64-bit CLINT timer compare value safely. */
static inline void eriscv_mcu_clint_set_mtimecmp(eriscv_mcu_u64 value) {
  eriscv_mcu_mmio_write32(ERISCV_MCU_CLINT_BASE + ERISCV_MCU_CLINT_MTIMECMP + 4u, 0xffffffffu);
  eriscv_mcu_mmio_write32(ERISCV_MCU_CLINT_BASE + ERISCV_MCU_CLINT_MTIMECMP, (eriscv_mcu_u32)value);
  eriscv_mcu_mmio_write32(ERISCV_MCU_CLINT_BASE + ERISCV_MCU_CLINT_MTIMECMP + 4u,
                       (eriscv_mcu_u32)(value >> 32));
}

/** @brief Set one PLIC source priority (0 disables notification). */
static inline void eriscv_mcu_plic_set_priority(eriscv_mcu_u32 source_id, eriscv_mcu_u32 priority) {
  if (source_id != 0u && source_id <= ERISCV_MCU_PLIC_SOURCES) {
    eriscv_mcu_mmio_write32(ERISCV_MCU_PLIC_BASE + ERISCV_MCU_PLIC_PRIORITY(source_id), priority & 7u);
  }
}

/** @brief Enable or disable one PLIC source for hart 0. */
static inline void eriscv_mcu_plic_set_enabled(eriscv_mcu_u32 source_id, int enabled) {
  eriscv_mcu_u32 address;
  eriscv_mcu_u32 value;

  if (source_id == 0u || source_id > ERISCV_MCU_PLIC_SOURCES) {
    return;
  }
  address = ERISCV_MCU_PLIC_BASE + ERISCV_MCU_PLIC_ENABLE + 4u * (source_id >> 5);
  value = eriscv_mcu_mmio_read32(address);
  if (enabled) {
    value |= 1u << (source_id & 31u);
  } else {
    value &= ~(1u << (source_id & 31u));
  }
  eriscv_mcu_mmio_write32(address, value);
}

/** @brief Set the hart-0 PLIC notification threshold. */
static inline void eriscv_mcu_plic_set_threshold(eriscv_mcu_u32 threshold) {
  eriscv_mcu_mmio_write32(ERISCV_MCU_PLIC_BASE + ERISCV_MCU_PLIC_THRESHOLD, threshold & 7u);
}

/** @brief Claim the highest-priority pending PLIC source, or zero. */
static inline eriscv_mcu_u32 eriscv_mcu_plic_claim(void) {
  return eriscv_mcu_mmio_read32(ERISCV_MCU_PLIC_BASE + ERISCV_MCU_PLIC_CLAIM);
}

/** @brief Complete a previously claimed PLIC source. */
static inline void eriscv_mcu_plic_complete(eriscv_mcu_u32 source_id) {
  eriscv_mcu_mmio_write32(ERISCV_MCU_PLIC_BASE + ERISCV_MCU_PLIC_CLAIM, source_id);
}

/** @brief Set GPIO output-enable bits. */
static inline void eriscv_mcu_gpio_set_direction(eriscv_mcu_u32 bits) {
  eriscv_mcu_mmio_write32(ERISCV_MCU_GPIO0_BASE + ERISCV_MCU_GPIO_DIR, bits);
}

/** @brief Write GPIO output bits. */
static inline void eriscv_mcu_gpio_write(eriscv_mcu_u32 value) {
  eriscv_mcu_mmio_write32(ERISCV_MCU_GPIO0_BASE + ERISCV_MCU_GPIO_OUT, value);
}

/** @brief Start the APB timer from zero with an optional IRQ. */
static inline void eriscv_mcu_timer_start(eriscv_mcu_u32 compare, int irq_en) {
  eriscv_mcu_mmio_write32(ERISCV_MCU_TIMER0_BASE + ERISCV_MCU_TIMER_COMPARE, compare);
  eriscv_mcu_u32 ctrl = ERISCV_MCU_TIMER_CTRL_ENABLE;
  if (irq_en) ctrl |= ERISCV_MCU_TIMER_CTRL_IRQ_EN;
  eriscv_mcu_mmio_write32(ERISCV_MCU_TIMER0_BASE + ERISCV_MCU_TIMER_COUNT, 0u);
  eriscv_mcu_mmio_write32(ERISCV_MCU_TIMER0_BASE + ERISCV_MCU_TIMER_CTRL, ctrl);
}

/** @brief Return nonzero when the APB timer has expired. */
static inline int eriscv_mcu_timer_expired(void) {
  return (eriscv_mcu_mmio_read32(ERISCV_MCU_TIMER0_BASE + ERISCV_MCU_TIMER_STATUS) & 1u) != 0u;
}

/** @brief Read the stable 64-bit CLINT mtime counter. */
static inline eriscv_mcu_u64 eriscv_mcu_clint_read_mtime(void) {
  eriscv_mcu_u32 lo, hi;
  do {
    hi = eriscv_mcu_mmio_read32(ERISCV_MCU_CLINT_BASE + ERISCV_MCU_CLINT_MTIME + 4u);
    lo = eriscv_mcu_mmio_read32(ERISCV_MCU_CLINT_BASE + ERISCV_MCU_CLINT_MTIME);
  } while (hi != eriscv_mcu_mmio_read32(ERISCV_MCU_CLINT_BASE + ERISCV_MCU_CLINT_MTIME + 4u));
  return ((eriscv_mcu_u64)hi << 32) | lo;
}

/* ── Clock and reset controller ── */
#define ERISCV_MCU_CLKRST_CLK_EN       0x00u
#define ERISCV_MCU_CLKRST_CLK_STATUS   0x04u
#define ERISCV_MCU_CLKRST_PERI_RST     0x08u
#define ERISCV_MCU_CLKRST_RST_CAUSE    0x0cu
#define ERISCV_MCU_CLKRST_SLEEP_CTRL   0x10u
#define ERISCV_MCU_CLKRST_WAKE_EN      0x14u
#define ERISCV_MCU_CLKRST_WAKE_STATUS  0x18u
#define ERISCV_MCU_CLKRST_SOFT_RST     0x1cu

#define ERISCV_MCU_CLK_UART   (1u << 0)
#define ERISCV_MCU_CLK_SPI    (1u << 1)
#define ERISCV_MCU_CLK_TIMER  (1u << 2)
#define ERISCV_MCU_CLK_GPIO   (1u << 3)
#define ERISCV_MCU_CLK_WDT    (1u << 4)
#define ERISCV_MCU_CLK_ALL    0x1fu

#define ERISCV_MCU_WAKE_UART_RX  (1u << 0)
#define ERISCV_MCU_WAKE_GPIO(n)  (1u << (1u + (eriscv_mcu_u32)(n)))
#define ERISCV_MCU_WAKE_MTIP     (1u << 9)
#define ERISCV_MCU_WAKE_WDT_PRE  (1u << 10)
#define ERISCV_MCU_SLEEP_REQ     (1u << 0)
#define ERISCV_MCU_WFI_SLEEP_EN  (1u << 2)

/** @brief Enable peripheral clock domains selected by mask. */
static inline void eriscv_mcu_clk_enable(eriscv_mcu_u32 mask) {
  eriscv_mcu_u32 value = eriscv_mcu_mmio_read32(ERISCV_MCU_CLK_RST_BASE +
                                                 ERISCV_MCU_CLKRST_CLK_EN);
  eriscv_mcu_mmio_write32(ERISCV_MCU_CLK_RST_BASE + ERISCV_MCU_CLKRST_CLK_EN,
                          value | (mask & ERISCV_MCU_CLK_ALL));
}

/** @brief Disable selected peripheral clock domains. */
static inline void eriscv_mcu_clk_disable(eriscv_mcu_u32 mask) {
  eriscv_mcu_u32 value = eriscv_mcu_mmio_read32(ERISCV_MCU_CLK_RST_BASE +
                                                 ERISCV_MCU_CLKRST_CLK_EN);
  eriscv_mcu_mmio_write32(ERISCV_MCU_CLK_RST_BASE + ERISCV_MCU_CLKRST_CLK_EN,
                          value & ~(mask & ERISCV_MCU_CLK_ALL));
}

/** @brief Return effective peripheral clock-enable state. */
static inline eriscv_mcu_u32 eriscv_mcu_clk_status(void) {
  return eriscv_mcu_mmio_read32(ERISCV_MCU_CLK_RST_BASE + ERISCV_MCU_CLKRST_CLK_STATUS);
}

/** @brief Pulse reset for selected peripheral domains. */
static inline void eriscv_mcu_peripheral_reset(eriscv_mcu_u32 mask) {
  eriscv_mcu_mmio_write32(ERISCV_MCU_CLK_RST_BASE + ERISCV_MCU_CLKRST_PERI_RST,
                          mask & ERISCV_MCU_CLK_ALL);
}

/** @brief Return the latched power-on, external, watchdog, or software reset cause. */
static inline eriscv_mcu_u32 eriscv_mcu_reset_cause(void) {
  return eriscv_mcu_mmio_read32(ERISCV_MCU_CLK_RST_BASE + ERISCV_MCU_CLKRST_RST_CAUSE);
}

/** @brief Enable or disable automatic deep sleep on WFI. */
static inline void eriscv_mcu_wfi_sleep_enable(int enable) {
  eriscv_mcu_mmio_write32(ERISCV_MCU_CLK_RST_BASE + ERISCV_MCU_CLKRST_SLEEP_CTRL,
                          enable ? ERISCV_MCU_WFI_SLEEP_EN : 0u);
}

/** @brief Request sleep and execute WFI until an enabled wake source fires. */
static inline void eriscv_mcu_enter_sleep(void) {
  eriscv_mcu_mmio_write32(ERISCV_MCU_CLK_RST_BASE + ERISCV_MCU_CLKRST_SLEEP_CTRL,
                          ERISCV_MCU_SLEEP_REQ);
  __asm__ volatile ("fence iorw, iorw" ::: "memory");
  __asm__ volatile ("wfi");
}

/** @brief Enable wake sources selected by mask. */
static inline void eriscv_mcu_wake_enable(eriscv_mcu_u32 mask) {
  eriscv_mcu_u32 value = eriscv_mcu_mmio_read32(ERISCV_MCU_CLK_RST_BASE +
                                                 ERISCV_MCU_CLKRST_WAKE_EN);
  eriscv_mcu_mmio_write32(ERISCV_MCU_CLK_RST_BASE + ERISCV_MCU_CLKRST_WAKE_EN,
                          value | (mask & 0x7ffu));
}

/** @brief Disable wake sources selected by mask. */
static inline void eriscv_mcu_wake_disable(eriscv_mcu_u32 mask) {
  eriscv_mcu_u32 value = eriscv_mcu_mmio_read32(ERISCV_MCU_CLK_RST_BASE +
                                                 ERISCV_MCU_CLKRST_WAKE_EN);
  eriscv_mcu_mmio_write32(ERISCV_MCU_CLK_RST_BASE + ERISCV_MCU_CLKRST_WAKE_EN,
                          value & ~(mask & 0x7ffu));
}

/** @brief Return latched wake-source status. */
static inline eriscv_mcu_u32 eriscv_mcu_wake_status(void) {
  return eriscv_mcu_mmio_read32(ERISCV_MCU_CLK_RST_BASE + ERISCV_MCU_CLKRST_WAKE_STATUS);
}

/** @brief Clear selected latched wake-source bits. */
static inline void eriscv_mcu_wake_status_clear(eriscv_mcu_u32 mask) {
  eriscv_mcu_mmio_write32(ERISCV_MCU_CLK_RST_BASE + ERISCV_MCU_CLKRST_WAKE_STATUS,
                          mask & 0x7ffu);
}

/** @brief Request a warm software reset. */
static inline void eriscv_mcu_soft_reset(void) {
  eriscv_mcu_mmio_write32(ERISCV_MCU_CLK_RST_BASE + ERISCV_MCU_CLKRST_SOFT_RST, 1u);
}

/* ── Watchdog (WDT) ── */
#define ERISCV_MCU_WDT_CTRL       0x00u
#define ERISCV_MCU_WDT_TIMEOUT    0x04u
#define ERISCV_MCU_WDT_WINDOW     0x08u
#define ERISCV_MCU_WDT_FEED       0x0cu
#define ERISCV_MCU_WDT_STATUS     0x10u
#define ERISCV_MCU_WDT_LOCK       0x14u
#define ERISCV_MCU_WDT_PRETIMEOUT 0x18u
#define ERISCV_MCU_WDT_FEED_MAGIC 0xACCE55EDu
#define ERISCV_MCU_WDT_CTRL_ENABLE   (1u << 0)
#define ERISCV_MCU_WDT_CTRL_WINDOW   (1u << 1)
#define ERISCV_MCU_WDT_CTRL_IRQ_EN   (1u << 2)
#define ERISCV_MCU_WDT_STATUS_EXPIRED (1u << 0)
#define ERISCV_MCU_WDT_STATUS_RESET   (1u << 1)
#define ERISCV_MCU_WDT_STATUS_LOCKED  (1u << 2)
#define ERISCV_MCU_WDT_STATUS_PRETIMEOUT (1u << 3)

/** @brief Program watchdog timeout in system-clock cycles. */
static inline void eriscv_mcu_wdt_set_timeout(eriscv_mcu_u32 cycles) {
  eriscv_mcu_mmio_write32(ERISCV_MCU_WDT0_BASE + ERISCV_MCU_WDT_TIMEOUT, cycles);
}

/** @brief Program the watchdog feed-window opening threshold. */
static inline void eriscv_mcu_wdt_set_window(eriscv_mcu_u32 open_at_remaining_cycles) {
  eriscv_mcu_mmio_write32(ERISCV_MCU_WDT0_BASE + ERISCV_MCU_WDT_WINDOW,
                          open_at_remaining_cycles);
}

/** @brief Program watchdog pre-timeout remaining cycles. */
static inline void eriscv_mcu_wdt_set_pretimeout(eriscv_mcu_u32 remaining_cycles) {
  eriscv_mcu_mmio_write32(ERISCV_MCU_WDT0_BASE + ERISCV_MCU_WDT_PRETIMEOUT,
                          remaining_cycles);
}

/** @brief Enable watchdog reset and optionally its pre-timeout IRQ. */
static inline void eriscv_mcu_wdt_enable(int irq_en) {
  eriscv_mcu_u32 ctrl = ERISCV_MCU_WDT_CTRL_ENABLE;
  if (irq_en) ctrl |= ERISCV_MCU_WDT_CTRL_IRQ_EN;
  eriscv_mcu_mmio_write32(ERISCV_MCU_WDT0_BASE + ERISCV_MCU_WDT_CTRL, ctrl);
}

/** @brief Feed the watchdog with the required magic value. */
static inline void eriscv_mcu_wdt_feed(void) {
  eriscv_mcu_mmio_write32(ERISCV_MCU_WDT0_BASE + ERISCV_MCU_WDT_FEED, ERISCV_MCU_WDT_FEED_MAGIC);
}

/** @brief Lock watchdog configuration until reset. */
static inline void eriscv_mcu_wdt_lock(void) {
  eriscv_mcu_mmio_write32(ERISCV_MCU_WDT0_BASE + ERISCV_MCU_WDT_LOCK, 1u);
}

/** @brief Return watchdog status bits. */
static inline eriscv_mcu_u32 eriscv_mcu_wdt_status(void) {
  return eriscv_mcu_mmio_read32(ERISCV_MCU_WDT0_BASE + ERISCV_MCU_WDT_STATUS);
}

/** @brief Clear the sticky watchdog-expired status bit. */
static inline void eriscv_mcu_wdt_clear_expired(void) {
  eriscv_mcu_mmio_write32(ERISCV_MCU_WDT0_BASE + ERISCV_MCU_WDT_STATUS, ERISCV_MCU_WDT_STATUS_EXPIRED);
}

/** @brief Clear the sticky watchdog pre-timeout status bit. */
static inline void eriscv_mcu_wdt_clear_pretimeout(void) {
  eriscv_mcu_mmio_write32(ERISCV_MCU_WDT0_BASE + ERISCV_MCU_WDT_STATUS,
                          ERISCV_MCU_WDT_STATUS_PRETIMEOUT);
}

/** @brief Configure the UART baud divisor and enable polling TX/RX. */
void eriscv_mcu_uart_init(eriscv_mcu_u32 baud_divisor);
/** @brief Transmit one byte, blocking until hardware accepts it. */
void eriscv_mcu_uart_putc(char ch);
/** @brief Receive one byte, blocking until available. */
int eriscv_mcu_uart_getc(void);
/** @brief Transmit a NUL-terminated string; LF is emitted as CR/LF. */
void eriscv_mcu_uart_puts(const char *text);

/** @brief Initialise the non-blocking UART FIFO and its PLIC interrupt route. */
void eriscv_mcu_uart_async_init(eriscv_mcu_u32 baud_divisor);
/** @brief Queue one byte for asynchronous transmit; returns nonzero if accepted. */
int eriscv_mcu_uart_async_putc(char ch);
/** @brief Queue up to length bytes for asynchronous transmit; returns bytes queued. */
eriscv_mcu_u32 eriscv_mcu_uart_async_write(const char *data, eriscv_mcu_u32 length);
/** @brief Return a queued received byte, or -1 when none is available. */
int eriscv_mcu_uart_async_getc(void);
/** @brief Return nonzero while queued or hardware UART transmit remains active. */
int eriscv_mcu_uart_async_tx_pending(void);
/** @brief Return the count of bytes dropped by the asynchronous RX FIFO. */
eriscv_mcu_u32 eriscv_mcu_uart_async_rx_dropped(void);
/** @brief Service UART IRQ state; called by the external-IRQ dispatcher. */
void eriscv_mcu_uart_irq_handler(void);
/** @brief Start one aligned System SRAM-to-System SRAM DMA transfer. */
int eriscv_mcu_dma_start(eriscv_mcu_u32 source, eriscv_mcu_u32 destination,
                         eriscv_mcu_u32 length, int irq_enable);
/**  Start one direct System SRAM-to-UART0 TX byte stream. */
int eriscv_mcu_dma_uart_tx_start(eriscv_mcu_u32 source, eriscv_mcu_u32 length,
                                 int irq_enable);
/** @brief Start one linked System SRAM descriptor chain. */
int eriscv_mcu_dma_start_descriptor(volatile eriscv_mcu_dma_descriptor_t *head,
                                    int irq_enable);
/** @brief Return the DMA status register. */
eriscv_mcu_u32 eriscv_mcu_dma_status(void);
/** @brief Wait for completion or error, bounded by status polls. */
int eriscv_mcu_dma_wait(eriscv_mcu_u32 timeout_polls);
/** @brief Clear sticky DMA done/error status and deassert its IRQ source. */
void eriscv_mcu_dma_clear_status(void);
/** @brief Enable DMA PLIC source 5; global MEIE remains caller-controlled. */
void eriscv_mcu_dma_irq_enable(eriscv_mcu_u32 priority);
/** @brief Disable DMA PLIC source 5. */
void eriscv_mcu_dma_irq_disable(void);
/** @brief Service DMA source 5; applications may override completion hook. */
void eriscv_mcu_dma_irq_handler(void);
/** @brief Weak DMA completion hook, called after sticky status is cleared. */
void eriscv_mcu_dma_complete_handler(eriscv_mcu_u32 status);
/** @brief Weak external-IRQ hook that dispatches PLIC sources. */
void eriscv_mcu_machine_external_irq_handler(void);

/**
 * @brief Weak top-level trap hook for application override.
 * @return Resume PC. Dispatch MEI through eriscv_mcu_machine_external_irq_handler().
 */
eriscv_mcu_u32 eriscv_mcu_trap_handler(eriscv_mcu_u32 mcause, eriscv_mcu_u32 mepc,
                                  eriscv_mcu_u32 mtval);

#endif
