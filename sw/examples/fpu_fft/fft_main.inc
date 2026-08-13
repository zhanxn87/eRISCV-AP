#define FPU_FFT_REPORT_MAGIC 0x46505431u
#define FPU_FFT_REPORT_PASS  0x80000001u
#define FPU_FFT_REPORT_FAIL  0x40000001u

typedef struct {
  volatile eriscv_mcu_u32 done;
  eriscv_mcu_u32 magic;
  eriscv_mcu_u32 points;
  eriscv_mcu_u32 start;
  eriscv_mcu_u32 stop;
  eriscv_mcu_u32 fft_cycles;
  eriscv_mcu_u32 mismatch_count;
  eriscv_mcu_u32 fflags;
} fpu_fft_report_t;

volatile fpu_fft_report_t eriscv_fpu_fft_report;
static float fft_re[FPU_FFT_POINTS];
static float fft_im[FPU_FFT_POINTS];

static eriscv_mcu_u32 read_mcycle(void)
{
  eriscv_mcu_u32 value;

  __asm__ volatile ("csrr %0, mcycle" : "=r"(value) :: "memory");
  return value;
}

static float f32_from_bits(eriscv_mcu_u32 bits)
{
  union {
    eriscv_mcu_u32 bits;
    float value;
  } convert;

  convert.bits = bits;
  return convert.value;
}

static eriscv_mcu_u32 f32_bits(float value)
{
  union {
    eriscv_mcu_u32 bits;
    float value;
  } convert;

  convert.value = value;
  return convert.bits;
}

static eriscv_mcu_u32 reverse_bits(eriscv_mcu_u32 value)
{
  eriscv_mcu_u32 reversed = 0u;
  eriscv_mcu_u32 bit;

  for (bit = 0u; bit < FPU_FFT_LOG2; ++bit) {
    reversed = (reversed << 1) | (value & 1u);
    value >>= 1;
  }
  return reversed;
}

static void fft(void)
{
  eriscv_mcu_u32 index;
  eriscv_mcu_u32 size;

  for (index = 0u; index < FPU_FFT_POINTS; ++index) {
    eriscv_mcu_u32 reversed = reverse_bits(index);
    if (reversed > index) {
      float swap_re = fft_re[index];
      float swap_im = fft_im[index];
      fft_re[index] = fft_re[reversed];
      fft_im[index] = fft_im[reversed];
      fft_re[reversed] = swap_re;
      fft_im[reversed] = swap_im;
    }
  }

  for (size = 2u; size <= FPU_FFT_POINTS; size <<= 1) {
    eriscv_mcu_u32 half = size >> 1;
    eriscv_mcu_u32 step = FPU_FFT_POINTS / size;
    eriscv_mcu_u32 base;

    for (base = 0u; base < FPU_FFT_POINTS; base += size) {
      eriscv_mcu_u32 offset;
      for (offset = 0u; offset < half; ++offset) {
        eriscv_mcu_u32 even = base + offset;
        eriscv_mcu_u32 odd = even + half;
        eriscv_mcu_u32 twiddle = offset * step;
        float product_rr = f32_from_bits(fpu_fft_twiddle_re_bits[twiddle]) * fft_re[odd];
        float product_ii = f32_from_bits(fpu_fft_twiddle_im_bits[twiddle]) * fft_im[odd];
        float product_ri = f32_from_bits(fpu_fft_twiddle_re_bits[twiddle]) * fft_im[odd];
        float product_ir = f32_from_bits(fpu_fft_twiddle_im_bits[twiddle]) * fft_re[odd];
        float temp_re = product_rr - product_ii;
        float temp_im = product_ri + product_ir;
        float old_re = fft_re[even];
        float old_im = fft_im[even];

        fft_re[even] = old_re + temp_re;
        fft_im[even] = old_im + temp_im;
        fft_re[odd] = old_re - temp_re;
        fft_im[odd] = old_im - temp_im;
      }
    }
  }
}

int main(void)
{
  eriscv_mcu_u32 index;
  eriscv_mcu_u32 mismatch_count = 0u;
  eriscv_mcu_u32 fflags;
  eriscv_mcu_u32 start;
  eriscv_mcu_u32 stop;

  eriscv_fpu_fft_report.done = 0u;
  eriscv_fpu_fft_report.magic = FPU_FFT_REPORT_MAGIC;
  eriscv_fpu_fft_report.points = FPU_FFT_POINTS;
	eriscv_mcu_uart_init(ERISCV_MCU_UART_DIVISOR);
  eriscv_mcu_gpio_set_direction(1u);
  eriscv_mcu_fp_enable();
  eriscv_mcu_fp_clear_fflags();
  for (index = 0u; index < FPU_FFT_POINTS; ++index) {
    fft_re[index] = f32_from_bits(fpu_fft_input_re_bits[index]);
    fft_im[index] = f32_from_bits(fpu_fft_input_im_bits[index]);
  }
  start = read_mcycle();
  fft();
  stop = read_mcycle();
  eriscv_fpu_fft_report.start = start;
  eriscv_fpu_fft_report.stop = stop;
  eriscv_fpu_fft_report.fft_cycles = stop - start;
  for (index = 0u; index < FPU_FFT_POINTS; ++index) {
    if (f32_bits(fft_re[index]) != fpu_fft_reference_re_bits[index] ||
        f32_bits(fft_im[index]) != fpu_fft_reference_im_bits[index]) {
      mismatch_count += 1u;
    }
  }
  fflags = eriscv_mcu_fp_read_fflags();
  eriscv_fpu_fft_report.mismatch_count = mismatch_count;
  eriscv_fpu_fft_report.fflags = fflags;
  if (mismatch_count != 0u || (fflags & ERISCV_MCU_FFLAGS_NX) == 0u) {
    eriscv_fpu_fft_report.done = FPU_FFT_REPORT_FAIL;
    eriscv_mcu_gpio_write(mismatch_count == 0u ? 0xffu : mismatch_count);
    eriscv_mcu_uart_puts("eRISCV-M2 FPU " FPU_FFT_LABEL " FAIL\n");
  } else {
    eriscv_fpu_fft_report.done = FPU_FFT_REPORT_PASS;
    eriscv_mcu_gpio_write(1u);
    eriscv_mcu_uart_puts("eRISCV-M2 FPU " FPU_FFT_LABEL " PASS\n");
  }
  for (;;) {
  }
}
