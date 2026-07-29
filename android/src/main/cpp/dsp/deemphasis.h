#ifndef RTLSDR_DEEMPHASIS_H
#define RTLSDR_DEEMPHASIS_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * One-pole de-emphasis — same math that used to be embedded in demod_fm.c,
 * now extracted as an independent module because WFM stereo needs to apply
 * it twice (once per L/R channel), AFTER the pilot/L-R split and the audio
 * decimation — no longer once over the whole MPX before the split (the raw
 * MPX needs to survive intact until after the 38kHz demux; see
 * rtlsdr_shim.c, where fm_demod_init now runs with deemphasis_tau_us=0 for
 * WFM — the discriminator only delivers the raw MPX, without filtering
 * anything).
 */
typedef struct {
    float state;
    float alpha;
} deemphasis_t;

/* sample_rate_hz: rate at which the filter runs (post audio-decimation —
 * much lower than the MPX rate where de-emphasis used to run, but
 * mathematically equivalent: it's a low-frequency shelf filter, well below
 * the decimation cutoff). tau_us: 50 or 75 (Europe/world vs US/Korea). */
void deemphasis_init(deemphasis_t *d, float sample_rate_hz, float tau_us);

void deemphasis_process(deemphasis_t *d, const float *in, size_t count, float *out);

#ifdef __cplusplus
}
#endif

#endif
