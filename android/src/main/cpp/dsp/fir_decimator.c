#include "fir_decimator.h"

#include <math.h>
#include <stdlib.h>

#define FIR_PI 3.14159265358979323846f

int fir_decimator_init(fir_decimator_t *d, int decim_factor, int num_taps, float cutoff_normalized,
                        int complex_mode) {
    d->taps = (float *)malloc(sizeof(float) * (size_t)num_taps);
    d->hist_i = (float *)calloc((size_t)num_taps, sizeof(float));
    d->hist_q = complex_mode ? (float *)calloc((size_t)num_taps, sizeof(float)) : NULL;
    if (!d->taps || !d->hist_i || (complex_mode && !d->hist_q)) {
        return -1;
    }

    d->num_taps = num_taps;
    d->write_pos = 0;
    d->filled = 0;
    d->decim_factor = decim_factor;
    d->phase = 0;

    /* Hamming-windowed low-pass sinc, DC gain normalized to 1.0 — see the
     * rationale for two-stage decimation in docs/native_build.md. */
    int m = num_taps - 1;
    float sum = 0.0f;
    for (int n = 0; n < num_taps; n++) {
        float x = (float)n - (float)m / 2.0f;
        float sinc = (x == 0.0f) ? cutoff_normalized : sinf(FIR_PI * cutoff_normalized * x) / (FIR_PI * x);
        float window = 0.54f - 0.46f * cosf(2.0f * FIR_PI * (float)n / (float)m);
        float tap = sinc * window;
        d->taps[n] = tap;
        sum += tap;
    }
    if (sum != 0.0f) {
        for (int n = 0; n < num_taps; n++) {
            d->taps[n] /= sum;
        }
    }

    return 0;
}

void fir_decimator_destroy(fir_decimator_t *d) {
    free(d->taps);
    free(d->hist_i);
    free(d->hist_q);
    d->taps = NULL;
    d->hist_i = NULL;
    d->hist_q = NULL;
}

size_t fir_decimator_process(fir_decimator_t *d, const float *in_i, const float *in_q, size_t in_count, float *out_i,
                              float *out_q, size_t out_capacity) {
    size_t out_count = 0;
    int complex_mode = (d->hist_q != NULL);

    for (size_t n = 0; n < in_count; n++) {
        d->hist_i[d->write_pos] = in_i[n];
        if (complex_mode) {
            d->hist_q[d->write_pos] = in_q[n];
        }
        if (d->filled < d->num_taps) {
            d->filled++;
        }

        d->phase++;
        if (d->phase >= d->decim_factor) {
            d->phase = 0;
            if (d->filled == d->num_taps && out_count < out_capacity) {
                float acc_i = 0.0f;
                float acc_q = 0.0f;
                int idx = d->write_pos;
                for (int k = 0; k < d->num_taps; k++) {
                    acc_i += d->taps[k] * d->hist_i[idx];
                    if (complex_mode) {
                        acc_q += d->taps[k] * d->hist_q[idx];
                    }
                    idx--;
                    if (idx < 0) {
                        idx = d->num_taps - 1;
                    }
                }
                out_i[out_count] = acc_i;
                if (complex_mode && out_q) {
                    out_q[out_count] = acc_q;
                }
                out_count++;
            }
        }

        d->write_pos++;
        if (d->write_pos >= d->num_taps) {
            d->write_pos = 0;
        }
    }

    return out_count;
}
