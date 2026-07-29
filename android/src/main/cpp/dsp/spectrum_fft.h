#ifndef RTLSDR_SPECTRUM_FFT_H
#define RTLSDR_SPECTRUM_FFT_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Complex FFT (KissFFT) over a window of raw IQ samples (pre-decimation),
 * to give a view of the whole captured band — not the narrow channel the
 * demodulator uses. Used for the waterfall/spectrum (M5).
 */
typedef struct {
    void *cfg; /* kiss_fft_cfg */
    int fft_size;
    float *window;   /* Hann window coefficients, fft_size long */
    void *in_buf;  /* kiss_fft_cpx*, allocated once in spectrum_fft_init */
    void *out_buf; /* kiss_fft_cpx*, same */
} spectrum_fft_t;

int spectrum_fft_init(spectrum_fft_t *s, int fft_size);
void spectrum_fft_destroy(spectrum_fft_t *s);

/* in_i/in_q: exactly fft_size IQ samples (most recent). out_db: fft_size
 * magnitude values in dB, already reordered (fftshift) — out_db[0] is the
 * lower edge of the captured band (center frequency - half the sample
 * rate) and out_db[fft_size-1] is the upper edge, DC in the middle —
 * order ready to draw directly onto a spectrum/waterfall. */
void spectrum_fft_process(spectrum_fft_t *s, const float *in_i, const float *in_q, float *out_db);

#ifdef __cplusplus
}
#endif

#endif
