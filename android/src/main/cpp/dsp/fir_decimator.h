#ifndef RTLSDR_FIR_DECIMATOR_H
#define RTLSDR_FIR_DECIMATOR_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Generic low-pass (Hamming-windowed) FIR decimator — used both to decimate
 * the complex IQ (anti-aliasing before reducing the sample rate) and the
 * real audio post-discriminator (in_q/out_q = NULL in that case).
 *
 * "Naive" implementation: keeps a circular history and only computes the
 * dot product with the taps at decimation instants (every N input
 * samples) — correct and simple, cost O(num_taps) per OUTPUT (decimated)
 * sample, not per input sample.
 */
typedef struct {
    float *taps;
    int num_taps;
    float *hist_i;
    float *hist_q; /* NULL if used only for a real signal */
    int write_pos;
    int filled;
    int decim_factor;
    int phase;
} fir_decimator_t;

/* cutoff_normalized: 0..1, where 1.0 = Nyquist of the INPUT rate. Use
 * something like 0.9 / decim_factor to leave transition margin before the
 * next Nyquist (of the decimated rate). complex_mode = 1 to operate on
 * I/Q, 0 for a real signal (in_q/out_q ignored in fir_decimator_process). */
int fir_decimator_init(fir_decimator_t *d, int decim_factor, int num_taps, float cutoff_normalized, int complex_mode);
void fir_decimator_destroy(fir_decimator_t *d);

/* Processes in_count input samples; writes the decimated samples to out_i
 * (and out_q, if complex_mode) up to out_capacity; returns how many
 * decimated samples were written. in_q/out_q may be NULL in real mode. */
size_t fir_decimator_process(fir_decimator_t *d, const float *in_i, const float *in_q, size_t in_count, float *out_i,
                              float *out_q, size_t out_capacity);

#ifdef __cplusplus
}
#endif

#endif
