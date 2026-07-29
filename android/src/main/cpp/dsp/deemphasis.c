#include "deemphasis.h"

void deemphasis_init(deemphasis_t *d, float sample_rate_hz, float tau_us) {
    float tau = tau_us * 1e-6f;
    float dt = 1.0f / sample_rate_hz;
    d->alpha = dt / (tau + dt);
    d->state = 0.0f;
}

void deemphasis_process(deemphasis_t *d, const float *in, size_t count, float *out) {
    float state = d->state;
    float alpha = d->alpha;
    for (size_t n = 0; n < count; n++) {
        state += alpha * (in[n] - state);
        out[n] = state;
    }
    d->state = state;
}
