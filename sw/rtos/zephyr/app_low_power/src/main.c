/* Zephyr tickless idle smoke: CLINT timeout wakes controller-gated WFI. */

#include <zephyr/kernel.h>
#include <zephyr/sys/atomic.h>

#define ZEPHYR_RESULT_PASS 0x5a6b7c8du
#define ZEPHYR_RESULT_FAIL 0xdead0010u

volatile unsigned int eriscv_zephyr_result __attribute__((section(".noinit")));

K_SEM_DEFINE(wake_sem, 0, 1);

static atomic_t wake_count;
static struct k_timer wake_timer;

static void wake_timer_expiry(struct k_timer *timer)
{
	ARG_UNUSED(timer);
	atomic_inc(&wake_count);
	k_sem_give(&wake_sem);
}

int main(void)
{
	eriscv_zephyr_result = 0u;
	k_timer_init(&wake_timer, wake_timer_expiry, NULL);
	k_timer_start(&wake_timer, K_MSEC(1), K_NO_WAIT);

	/* Blocking here leaves only Zephyr's idle thread runnable; arch_cpu_idle()
	 * executes WFI and the SoC controller gates the core clock. */
	if (k_sem_take(&wake_sem, K_MSEC(20)) == 0 &&
	    atomic_get(&wake_count) == 1) {
		eriscv_zephyr_result = ZEPHYR_RESULT_PASS;
	} else {
		eriscv_zephyr_result = ZEPHYR_RESULT_FAIL;
	}

	for (;;) {
		k_sleep(K_FOREVER);
	}
}
