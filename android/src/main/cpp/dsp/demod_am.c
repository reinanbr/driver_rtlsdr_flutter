#include "demod_am.h"

#include <math.h>

/* DC blocker coefficient (one-pole high-pass): the closer to 1.0, the
 * lower the cutoff frequency. 0.995 cuts well below 100 Hz at the audio
 * rates used here (~32 kHz). */
#define AM_DC_BLOCK_COEFF 0.995f

void am_demod_init(am_demod_t *d) {
    d->dc_prev_in = 0.0f;
    d->dc_prev_out = 0.0f;
}

void am_demod_process(am_demod_t *d, const float *in_i, const float *in_q, size_t count, float *out_audio) {
    float dc_prev_in = d->dc_prev_in;
    float dc_prev_out = d->dc_prev_out;

    for (size_t n = 0; n < count; n++) {
        float i = in_i[n];
        float q = in_q[n];

        /* envelope detector: magnitude of the complex baseband */
        float envelope = sqrtf(i * i + q * q);

        /* DC blocker: removes the large offset left by the carrier */
        float dc_out = envelope - dc_prev_in + AM_DC_BLOCK_COEFF * dc_prev_out;
        dc_prev_in = envelope;
        dc_prev_out = dc_out;

        out_audio[n] = dc_out;
    }

    d->dc_prev_in = dc_prev_in;
    d->dc_prev_out = dc_prev_out;
}
