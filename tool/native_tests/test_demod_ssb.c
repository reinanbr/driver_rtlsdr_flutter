/*
 * Standalone correctness check for dsp/demod_ssb.c — no Android toolchain,
 * emulator or hardware needed, just a host C compiler. There's no CTest/
 * gtest harness in this repo (the DSP modules have historically only been
 * validated by ear on real hardware — see README.md's Tests section), so
 * this is a minimal, dependency-free stand-in specifically for the one
 * thing most likely to go subtly wrong in a phasing-method SSB
 * demodulator: a sign error that silently swaps which sideband gets
 * rejected. It feeds a synthetic single-tone complex baseband signal on
 * each side of DC and checks that demodulating with the matching sideband
 * recovers the tone, while demodulating with the OTHER sideband rejects
 * it (image suppression) — the exact property a sign mistake would break
 * without changing the "does it produce audio at all" behavior.
 *
 * Build & run:
 *   cc -std=c11 -O2 -o /tmp/test_demod_ssb \
 *     tool/native_tests/test_demod_ssb.c android/src/main/cpp/dsp/demod_ssb.c \
 *     -I android/src/main/cpp/dsp -lm && /tmp/test_demod_ssb
 */

#include <math.h>
#include <stdio.h>

#include "demod_ssb.h"

#define TEST_PI 3.14159265358979323846
#define SAMPLE_RATE_HZ 32000.0
#define NUM_SAMPLES 4000
#define TRANSIENT_SAMPLES 200 /* skipped when computing RMS — filter startup */

/* sign_hz > 0 generates energy on the +f (USB) side of DC; < 0 on the -f
 * (LSB) side — see demod_ssb.h's derivation comment for why s[n] =
 * i[n] + j*q[n] with a positive-frequency tone looks like this. */
static void generate_tone(double freq_hz, float *out_i, float *out_q, int count) {
    for (int n = 0; n < count; n++) {
        double theta = 2.0 * TEST_PI * freq_hz * (double)n / SAMPLE_RATE_HZ;
        out_i[n] = (float)cos(theta);
        out_q[n] = (float)sin(theta);
    }
}

static double rms_from(const float *x, int count, int skip) {
    double sum_sq = 0.0;
    int n_used = 0;
    for (int n = skip; n < count; n++) {
        sum_sq += (double)x[n] * (double)x[n];
        n_used++;
    }
    return sqrt(sum_sq / (double)n_used);
}

/* sideband: 0 = USB, 1 = LSB (matches ssb_demod_t / demod_mode_t). */
static double demod_rms(int sideband, const float *in_i, const float *in_q, int count) {
    ssb_demod_t d;
    if (ssb_demod_init(&d, sideband) != 0) {
        fprintf(stderr, "ssb_demod_init failed\n");
        return -1.0;
    }
    float out[NUM_SAMPLES];
    ssb_demod_process(&d, in_i, in_q, (size_t)count, out);
    ssb_demod_destroy(&d);
    return rms_from(out, count, TRANSIENT_SAMPLES);
}

static int check_case(const char *label, double tone_hz, int sideband_demod, int expect_pass) {
    float in_i[NUM_SAMPLES];
    float in_q[NUM_SAMPLES];
    generate_tone(tone_hz, in_i, in_q, NUM_SAMPLES);

    double rms = demod_rms(sideband_demod, in_i, in_q, NUM_SAMPLES);
    int ok = expect_pass ? (rms > 0.5) : (rms < 0.05);

    printf("%-45s rms=%.4f  %s\n", label, rms, ok ? "OK" : "FAIL");
    return ok;
}

int main(void) {
    int all_ok = 1;

    /* +1000Hz tone (USB-side energy): USB demod should recover it, LSB
     * demod should reject it (image). */
    all_ok &= check_case("+1000Hz tone, demod as USB (expect pass)", 1000.0, /*sideband=*/0, /*expect_pass=*/1);
    all_ok &= check_case("+1000Hz tone, demod as LSB (expect reject)", 1000.0, /*sideband=*/1, /*expect_pass=*/0);

    /* -1000Hz tone (LSB-side energy): mirror image of the above. */
    all_ok &= check_case("-1000Hz tone, demod as LSB (expect pass)", -1000.0, /*sideband=*/1, /*expect_pass=*/1);
    all_ok &= check_case("-1000Hz tone, demod as USB (expect reject)", -1000.0, /*sideband=*/0, /*expect_pass=*/0);

    /* A second frequency near the other end of a voice passband, same
     * expectations — catches a Hilbert transformer that only behaves near
     * one frequency. */
    all_ok &= check_case("+2200Hz tone, demod as USB (expect pass)", 2200.0, /*sideband=*/0, /*expect_pass=*/1);
    all_ok &= check_case("+2200Hz tone, demod as LSB (expect reject)", 2200.0, /*sideband=*/1, /*expect_pass=*/0);

    if (!all_ok) {
        printf("\nFAILED\n");
        return 1;
    }
    printf("\nAll SSB image-rejection checks passed.\n");
    return 0;
}
