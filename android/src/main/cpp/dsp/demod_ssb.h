#ifndef RTLSDR_DEMOD_SSB_H
#define RTLSDR_DEMOD_SSB_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * SSB demodulation, phasing method. Given the complex baseband s[n] =
 * i[n] + j*q[n] (same convention as demod_fm.c's discriminator), the
 * desired sideband's audio is NOT simply i[n] — that folds together
 * whatever is at +f and -f in s[n] (Real{s[n]} is always Hermitian-
 * symmetric), so a real signal on the unwanted side of the tuned
 * frequency would leak straight into the audio. Instead:
 *
 *   audio_usb[n] = i[n-d] - hilbert(q)[n]   (keeps +f, rejects -f)
 *   audio_lsb[n] = i[n-d] + hilbert(q)[n]   (keeps -f, rejects +f)
 *
 * where hilbert(q) is q[n] phase-shifted by 90 degrees (a windowed,
 * linear-phase FIR approximation of the ideal Hilbert transform) and d is
 * that FIR's group delay — i[n] needs the same plain delay so both line
 * up in time before combining. See tool/native_tests/test_demod_ssb.c for
 * a synthetic-signal check that this actually rejects the correct image.
 *
 * Validated end-to-end on a real RTL2838U dongle (example app, both USB
 * and LSB, tuned into the commercial FM band): the pipeline runs at
 * plausible RF/audio levels with no crash and the correct 1-channel
 * output — see the "DSP pipeline: mode 3/4" log line from dsp_thread_main.
 * Not yet confirmed by ear against a real SSB voice transmission (that
 * needs HF, not the VHF band this was tested on) — the image-rejection
 * math itself is what tool/native_tests/test_demod_ssb.c checks.
 */
typedef struct {
    int sideband; /* 0 = USB, 1 = LSB */

    float *hilbert_taps;
    int num_taps; /* odd; taps[k] = 0 for k == center or (k - center) even */
    float *hist_q;
    int write_pos;

    float *delay_i; /* plain circular delay, length == the Hilbert FIR's
                      * (num_taps - 1) / 2 group delay */
    int delay_len;
    int delay_pos;
} ssb_demod_t;

/* sideband: 0 = USB, 1 = LSB. Returns 0 on success, <0 on allocation failure. */
int ssb_demod_init(ssb_demod_t *d, int sideband);
void ssb_demod_destroy(ssb_demod_t *d);

void ssb_demod_process(ssb_demod_t *d, const float *in_i, const float *in_q, size_t count, float *out_audio);

#ifdef __cplusplus
}
#endif

#endif
