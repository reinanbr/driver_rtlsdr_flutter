#ifndef RTLSDR_DEMOD_FM_H
#define RTLSDR_DEMOD_FM_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Generic quadrature discriminator, shared between WFM (wideband
 * commercial broadcast radio) and NFM (narrowband, amateur radio/PMR) —
 * the discriminator math is identical in both cases; only the expected
 * maximum deviation and de-emphasis change. Mono only — no stereo/RDS.
 */
typedef struct {
    float prev_i;
    float prev_q;
    float deemph_state;
    float deemph_alpha;
    float gain;
    int deemphasis_enabled;
} fm_demod_t;

/* sample_rate_hz: complex INPUT rate of the discriminator (post IQ
 * decimation). max_deviation_hz: expected maximum deviation (75000 for
 * WFM, ~5000 for NFM) — sets the scale gain to +-1.0 audio amplitude.
 * deemphasis_tau_us: 50 or 75 for WFM; use <= 0 to disable (NFM doesn't
 * use broadcast pre-emphasis). */
void fm_demod_init(fm_demod_t *d, float sample_rate_hz, float max_deviation_hz, float deemphasis_tau_us);

void fm_demod_process(fm_demod_t *d, const float *in_i, const float *in_q, size_t count, float *out_audio);

#ifdef __cplusplus
}
#endif

#endif
