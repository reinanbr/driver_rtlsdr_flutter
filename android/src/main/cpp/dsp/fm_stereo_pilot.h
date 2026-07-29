#ifndef RTLSDR_FM_STEREO_PILOT_H
#define RTLSDR_FM_STEREO_PILOT_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * 2nd-order PLL locked to the 19kHz pilot of the FM stereo multiplex —
 * runs directly on the raw MPX (audio_pre, no de-emphasis, no dedicated
 * bandpass: the PLL's own narrow loop already acts as a tracking filter,
 * a standard technique used by open-source FM stereo decoders like
 * SoftFM — an explicit BPF would only add group delay to compensate for
 * later, with no real gain).
 *
 * Generates the 2nd and 3rd order harmonics via double-angle/sum
 * identities from the NCO's own phase — cos(2θ)/sin(2θ) for the 38kHz L-R
 * demux (already used in stereo), cos(3θ)/sin(3θ) for the RDS
 * downconversion at 57kHz (used only from the RDS decoder onward) —
 * without needing a second/third NCO:
 *   sin(2θ) = 2·sinθ·cosθ            cos(2θ) = cos²θ − sin²θ
 *   sin(3θ) = sin(2θ)·cosθ + cos(2θ)·sinθ    cos(3θ) = cos(2θ)·cosθ − sin(2θ)·sinθ
 *
 * WARNING (not validated on real hardware — no dongle available in the
 * development environment): the loop gains (~8Hz bandwidth, zeta~0.707)
 * and the lock amplitude thresholds in PILOT_LOCK_AMPLITUDE/
 * PILOT_UNLOCK_AMPLITUDE (fm_stereo_pilot.c) are starting-point estimates.
 * Expected to need tuning against a real dongle — especially if the
 * dongle's crystal frequency offset (common in cheap dongles, can reach
 * hundreds of Hz) exceeds the loop's capture range, which would prevent
 * lock even with a good RF signal.
 */
typedef struct {
    float theta; /* NCO phase, rad, wrapped to ±pi */
    float freq;  /* NCO frequency, rad/sample */
    float alpha; /* PI loop proportional gain */
    float beta;  /* PI loop integral gain */

    /* Pilot amplitude detector (lock decision) — 1st-order LPF over the
     * I/Q correlation with the NCO itself; does not feed back into the
     * phase loop, only reports locked/last_amplitude. */
    float lock_lpf_i;
    float lock_lpf_q;
    float lock_alpha;
    float last_amplitude;

    int locked;
    int debounce_counter;
} fm_stereo_pilot_t;

void fm_stereo_pilot_init(fm_stereo_pilot_t *p, float sample_rate_hz);

/* Processes `count` samples of the raw MPX (audio_pre, no de-emphasis).
 * Writes cos(2θ)/sin(2θ)/cos(3θ)/sin(3θ) into `count`-sized arrays
 * supplied by the caller — any of the 4 pointers may be NULL to skip that
 * output (e.g. the stereo demux only needs cos2wt; sin2wt/cos3wt/sin3wt
 * stay NULL until the RDS decoder is added). */
void fm_stereo_pilot_process(fm_stereo_pilot_t *p, const float *mpx, size_t count, float *cos2wt, float *sin2wt,
                              float *cos3wt, float *sin3wt);

int fm_stereo_pilot_locked(const fm_stereo_pilot_t *p);
float fm_stereo_pilot_amplitude(const fm_stereo_pilot_t *p);

#ifdef __cplusplus
}
#endif

#endif
