#include "demod_ssb.h"

#include <math.h>
#include <stdlib.h>

#define SSB_PI 3.14159265358979323846f
/* Same tap count as fir_decimator.c's FIR_NUM_TAPS, for consistency — odd,
 * so the ideal Hilbert response has a well-defined center (zero) tap. */
#define SSB_HILBERT_TAPS 63

int ssb_demod_init(ssb_demod_t *d, int sideband) {
    d->sideband = sideband;
    d->num_taps = SSB_HILBERT_TAPS;
    d->delay_len = (d->num_taps - 1) / 2;

    d->hilbert_taps = (float *)malloc(sizeof(float) * (size_t)d->num_taps);
    d->hist_q = (float *)calloc((size_t)d->num_taps, sizeof(float));
    d->delay_i = (float *)calloc((size_t)d->delay_len, sizeof(float));
    if (!d->hilbert_taps || !d->hist_q || !d->delay_i) {
        return -1;
    }

    /* Windowed ideal Hilbert transformer: h[k] = 2/(pi*k) for k odd
     * (k = n - center), 0 for k even (including the center, k=0) — same
     * Hamming window formula as fir_decimator.c, for consistency. */
    int center = d->delay_len;
    int m = d->num_taps - 1;
    for (int n = 0; n < d->num_taps; n++) {
        int k = n - center;
        float tap = (k == 0 || (k % 2) == 0) ? 0.0f : (2.0f / (SSB_PI * (float)k));
        float window = 0.54f - 0.46f * cosf(2.0f * SSB_PI * (float)n / (float)m);
        d->hilbert_taps[n] = tap * window;
    }

    d->write_pos = 0;
    d->delay_pos = 0;
    return 0;
}

void ssb_demod_destroy(ssb_demod_t *d) {
    free(d->hilbert_taps);
    free(d->hist_q);
    free(d->delay_i);
    d->hilbert_taps = NULL;
    d->hist_q = NULL;
    d->delay_i = NULL;
}

void ssb_demod_process(ssb_demod_t *d, const float *in_i, const float *in_q, size_t count, float *out_audio) {
    float sign = (d->sideband == 0) ? -1.0f : 1.0f; /* USB: i - hilbert(q); LSB: i + hilbert(q) */
    int num_taps = d->num_taps;
    int delay_len = d->delay_len;

    for (size_t n = 0; n < count; n++) {
        d->hist_q[d->write_pos] = in_q[n];

        /* Direct-form FIR convolution — same circular-history walk as
         * fir_decimator_process, taps[0] pairing with the sample just
         * written (the newest one). */
        float q_hat = 0.0f;
        int idx = d->write_pos;
        for (int k = 0; k < num_taps; k++) {
            q_hat += d->hilbert_taps[k] * d->hist_q[idx];
            idx--;
            if (idx < 0) {
                idx = num_taps - 1;
            }
        }

        d->write_pos++;
        if (d->write_pos >= num_taps) {
            d->write_pos = 0;
        }

        /* Plain delay on I, matching the Hilbert FIR's group delay
         * (delay_len samples) so i[n-delay_len] and hilbert(q)[n] line up
         * in time before combining. */
        float i_delayed = d->delay_i[d->delay_pos];
        d->delay_i[d->delay_pos] = in_i[n];
        d->delay_pos++;
        if (d->delay_pos >= delay_len) {
            d->delay_pos = 0;
        }

        out_audio[n] = i_delayed + sign * q_hat;
    }
}
