#include "demod_fm.h"

#include <math.h>

#define FM_PI 3.14159265358979323846f

void fm_demod_init(fm_demod_t *d, float sample_rate_hz, float max_deviation_hz, float deemphasis_tau_us) {
    d->prev_i = 0.0f;
    d->prev_q = 1.0f; /* avoids a degenerate atan2(0,0) on the first sample */
    d->deemph_state = 0.0f;

    if (deemphasis_tau_us > 0.0f) {
        float tau = deemphasis_tau_us * 1e-6f;
        float dt = 1.0f / sample_rate_hz;
        d->deemph_alpha = dt / (tau + dt);
        d->deemphasis_enabled = 1;
    } else {
        d->deemph_alpha = 0.0f;
        d->deemphasis_enabled = 0;
    }

    /* Scales the discriminator output (radians/sample) so that the
     * maximum deviation maps to +-1.0 audio amplitude. */
    d->gain = sample_rate_hz / (2.0f * FM_PI * max_deviation_hz);
}

void fm_demod_process(fm_demod_t *d, const float *in_i, const float *in_q, size_t count, float *out_audio) {
    float prev_i = d->prev_i;
    float prev_q = d->prev_q;
    float deemph = d->deemph_state;
    float alpha = d->deemph_alpha;
    float gain = d->gain;
    int deemphasis_enabled = d->deemphasis_enabled;

    for (size_t n = 0; n < count; n++) {
        float i = in_i[n];
        float q = in_q[n];

        /* conjugate-product discriminator: d[n] = s[n] * conj(s[n-1]) */
        float di = i * prev_i + q * prev_q;
        float dq = q * prev_i - i * prev_q;
        float raw = atan2f(dq, di) * gain;

        if (deemphasis_enabled) {
            deemph += alpha * (raw - deemph);
            out_audio[n] = deemph;
        } else {
            out_audio[n] = raw;
        }

        prev_i = i;
        prev_q = q;
    }

    d->prev_i = prev_i;
    d->prev_q = prev_q;
    d->deemph_state = deemph;
}
