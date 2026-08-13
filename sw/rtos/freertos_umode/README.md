# FreeRTOS U-mode task-isolation profile

This P8C increment keeps the upstream FreeRTOS submodule unchanged. A local
linker wrapper replaces only the initial scheduler `ret` with the upstream
context-restore `mret` path. Four static tasks start in U-mode with independent
4 KiB PMP-protected DTCM stack/data regions. A local task-indexed PMP template
is loaded after every FreeRTOS scheduler selection; duplicate registration and
a fifth task are rejected.

> **Status: P9.2 functional smoke closed.** The default four-task delay→notify
> ModelSim run completes only after user3 verifies the three notification wakes,
> three notification gives, user0–2 exits, and the user1 wake-cycle record.

## P8C scope

The intended four-task application exercises a delay→notify chain:

| Task | Private DTCM | Blocking | Wake source | Syscalls | Completion |
|------|--------------|----------|-------------|----------|------------|
| user0 | USER0 | `delay(3)` | CLINT tick | `delay`, `notify_give`, `exit` | recorded by M-mode exit handler |
| user1 | USER1 | `notify_wait` | user0 `notify_give` | `notify_wait`, `notify_give`, `exit` | wake record + exit |
| user2 | USER2 | `notify_wait` | user1 `notify_give` | `notify_wait`, `notify_give`, `exit` | wake + exit |
| user3 | USER3 | `notify_wait` | user2 `notify_give` | `notify_wait`, `exit` | final gate → `result=1` |

Task 0 (scheduled first) initiates the chain with a one-tick delay. Tasks 1–3
block on notification, then wake and pass the notification forward. Task 3 is
the final gate: it verifies the three task-exit completions, all three
notify-wake/given events, and the user1 wake-cycle record before publishing
`eriscv_freertos_umode_result = 1`.

The implemented syscall ABI defines five services through the
`freertos_risc_v_application_exception_handler` dispatch:

| Syscall | Service (`a7`) | Argument (`a0`) | Returns |
|---------|----------------|-----------------|---------|
| `yield` | 1 | — | `vTaskSwitchContext()` |
| `exit` | 2 | — | `vTaskDelete(0)` (only when progress state matches) |
| `delay` | 3 | ticks (1–1000) | `vTaskDelay(argument)` |
| `notify_give` | 4 | target task index (0–3) | `xTaskNotifyGive(target)` |
| `notify_wait` | 5 | must be 0 | `ulTaskNotifyTake(pdTRUE, portMAX_DELAY)` |

Unknown services trigger `vAssertCalled` (fail-stop `0xdead0001`). All
services validate arguments; invalid arguments also trigger fail-stop.

## Memory budget (fixed, static allocation)

| Region | Base | Size | Purpose |
|--------|------|------|---------|
| USER0_DMEM | `0x11000000` | 4 KiB | Task 0 private stack + progress |
| USER1_DMEM | `0x11001000` | 4 KiB | Task 1 private stack + progress |
| USER2_DMEM | `0x11002000` | 4 KiB | Task 2 private stack + progress |
| USER3_DMEM | `0x11003000` | 4 KiB | Task 3 private stack + progress |
| KERNEL_DMEM | `0x11004000` | 48 KiB | Kernel data, BSS, stacks, TCBs |

**No-direct-kernel-call rule:** U-mode tasks must not directly call kernel API
functions. All kernel services are accessed exclusively through the approved
syscall ABI (`ECALL` with `a7` = service number). Direct calls from U-mode
will fault on PMP-protected kernel memory.

Dynamic allocation (`configSUPPORT_DYNAMIC_ALLOCATION=0`) and heap are
permanently disabled in this profile.

## PMP protection

Two PMP entries are active during U-mode execution:

| Entry | Region | Permissions | Encoding |
|-------|--------|-------------|----------|
| pmpaddr0 | ITCM `[0x10000000, 0x10010000)` | RX (NAPOT) | `0x04001fff` |
| pmpaddr1 | Task-specific 4 KiB DTCM | RW (NAPOT) | `napot_4k(base)` |

The PMP template is reloaded on every scheduler context switch via the
linker-wrapped `__wrap_vTaskSwitchContext`. The idle task (M-mode) inherits
the prior unlocked template.

## PMP negative registration

Duplicate task registration, a fifth task, a null task handle, and misaligned
base addresses are rejected by `eriscv_umode_pmp_register`. The current
negative run exercises duplicate registration only; the other inputs still
need separate coverage.

```sh
python3 eriscv-m2/sw/tools/run_freertos_umode_sim.py --pmp-negative
```

## Run the reproducible ModelSim smoke

```sh
# Four-task delay/notify chain + PMP reload/isolation
python3 eriscv-m2/sw/tools/run_freertos_umode_sim.py

# Unknown-syscall fail-stop
python3 eriscv-m2/sw/tools/run_freertos_umode_sim.py --bad-syscall

# PMP negative-registration fail-stop
python3 eriscv-m2/sw/tools/run_freertos_umode_sim.py --pmp-negative
```
