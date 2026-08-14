# eRISCV-AP APB peripheral RTL

This directory is the AP-local source for the legacy 32-bit APB peripherals
used by the bootstrap SoC: clock/reset control, GPIO, SPI, timer, UART, and
watchdog. They are retained for the AP AXI-to-APB slave path; address decode,
clock wiring, and interrupt routing remain under `rtl/soc/`.

Upstream provenance and license are recorded in `LOCK.md` and `LICENSE`.
