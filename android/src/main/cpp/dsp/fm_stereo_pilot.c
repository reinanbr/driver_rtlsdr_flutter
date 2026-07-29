#include "fm_stereo_pilot.h"

#include <math.h>

#define STEREO_PI 3.14159265358979323846f
#define STEREO_PILOT_HZ 19000.0f

/* Target loop bandwidth and damping of the PI loop — starting point, not
 * validated on real hardware, see WARNING in fm_stereo_pilot.h. */
#define PLL_LOOP_BW_HZ 8.0f
#define PLL_ZETA 0.707f

/* Time constant of the pilot amplitude detector's LPF. */
#define LOCK_LPF_TAU_S 0.030f

/* Amplitude thresholds for the lock decision, with hysteresis (like the
 * existing squelch in rtlsdr_shim.c) — locking requires a higher amplitude
 * than unlocking, avoiding flapping at the edge. Values not calibrated
 * against a real signal, see WARNING in the header. */
#define PILOT_LOCK_AMPLITUDE 0.010f
#define PILOT_UNLOCK_AMPLITUDE 0.006f

/* Debounce in number of calls to fm_stereo_pilot_process (each call covers
 * one block from the DSP thread, typically a few ms) — requires N
 * consecutive blocks on the opposite side of the threshold before
 * switching state. */
#define PILOT_LOCK_DEBOUNCE_BLOCKS 10

void fm_stereo_pilot_init(fm_stereo_pilot_t *p, float sample_rate_hz) {
    p->theta = 0.0f;
    p->freq = 2.0f * STEREO_PI * STEREO_PILOT_HZ / sample_rate_hz;

    float loop_bw = 2.0f * STEREO_PI * PLL_LOOP_BW_HZ / sample_rate_hz;
    float denom = 1.0f + 2.0f * PLL_ZETA * loop_bw + loop_bw * loop_bw;
    p->alpha = 4.0f * PLL_ZETA * loop_bw / denom;
    p->beta = 4.0f * loop_bw * loop_bw / denom;

    p->lock_lpf_i = 0.0f;
    p->lock_lpf_q = 0.0f;
    float dt = 1.0f / sample_rate_hz;
    p->lock_alpha = dt / (LOCK_LPF_TAU_S + dt);
    p->last_amplitude = 0.0f;

    p->locked = 0;
    p->debounce_counter = 0;
}

void fm_stereo_pilot_process(fm_stereo_pilot_t *p, const float *mpx, size_t count, float *cos2wt, float *sin2wt,
                              float *cos3wt, float *sin3wt) {
    float theta = p->theta;
    float freq = p->freq;
    float alpha = p->alpha;
    float beta = p->beta;
    float lock_lpf_i = p->lock_lpf_i;
    float lock_lpf_q = p->lock_lpf_q;
    float lock_alpha = p->lock_alpha;

    for (size_t n = 0; n < count; n++) {
        float nco_sin = sinf(theta);
        float nco_cos = cosf(theta);

        /* PLL phase detector: error against the 19kHz pilot present in
         * the raw MPX. */
        float error = mpx[n] * nco_sin;
        freq += beta * error;
        theta += freq + alpha * error;
        if (theta > STEREO_PI) {
            theta -= 2.0f * STEREO_PI;
        } else if (theta < -STEREO_PI) {
            theta += 2.0f * STEREO_PI;
        }

        lock_lpf_i += lock_alpha * (mpx[n] * nco_cos - lock_lpf_i);
        lock_lpf_q += lock_alpha * (mpx[n] * nco_sin - lock_lpf_q);

        /* Harmonics via double-angle/sum identities — see header. */
        float s2 = 2.0f * nco_sin * nco_cos;
        float c2 = nco_cos * nco_cos - nco_sin * nco_sin;
        if (cos2wt) cos2wt[n] = c2;
        if (sin2wt) sin2wt[n] = s2;

        if (cos3wt) cos3wt[n] = c2 * nco_cos - s2 * nco_sin;
        if (sin3wt) sin3wt[n] = s2 * nco_cos + c2 * nco_sin;
    }

    p->theta = theta;
    p->freq = freq;
    p->lock_lpf_i = lock_lpf_i;
    p->lock_lpf_q = lock_lpf_q;

    float amplitude = sqrtf(lock_lpf_i * lock_lpf_i + lock_lpf_q * lock_lpf_q);
    p->last_amplitude = amplitude;

    float threshold = p->locked ? PILOT_UNLOCK_AMPLITUDE : PILOT_LOCK_AMPLITUDE;
    int amplitude_ok = (amplitude >= threshold);

    if (amplitude_ok == p->locked) {
        p->debounce_counter = 0;
    } else {
        p->debounce_counter++;
        if (p->debounce_counter >= PILOT_LOCK_DEBOUNCE_BLOCKS) {
            p->locked = amplitude_ok;
            p->debounce_counter = 0;
        }
    }
}

int fm_stereo_pilot_locked(const fm_stereo_pilot_t *p) {
    return p->locked;
}

float fm_stereo_pilot_amplitude(const fm_stereo_pilot_t *p) {
    return p->last_amplitude;
}
