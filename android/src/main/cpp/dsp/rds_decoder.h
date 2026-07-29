#ifndef RTLSDR_RDS_DECODER_H
#define RTLSDR_RDS_DECODER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * RDS (RBDS) decoder: coherent downconversion of the 57kHz subcarrier
 * (3rd harmonic of the 19kHz pilot, reusing the same PLL as stereo — see
 * dsp/fm_stereo_pilot.h) + decimation, symbol clock recovery (Gardner) at
 * the biphase chip rate (2375Hz = 2x the 1187.5Hz bit rate), BPSK Costas
 * loop to correct residual phase rotation, biphase pair combining +
 * differential decoding -> bitstream, 26-bit block sync (CRC/offset words
 * A/B/C/C'/D) and group parsing (PI, PTY, TP, TA, PS via group 0A,
 * RadioText via group 2A/2B).
 *
 * Constants verified against an actively maintained open-source reference
 * implementation (redsea, github.com/windytan/redsea — MIT): the CRC
 * generator polynomial, the 5 offset word/syndrome values, and the 26-row
 * parity check matrix were checked byte for byte against that source (not
 * trusted from memory) — see RDS_PARITY_CHECK_MATRIX/rds_offset_for_syndrome
 * in rds_decoder.c. The rest (DSP front-end: downconversion, Gardner,
 * Costas, biphase combining) is an original implementation, simpler than
 * references like redsea (which uses liquid-dsp and more sophisticated
 * fractional resampling) — see WARNING below.
 *
 * WARNING (not validated on real hardware — no dongle available in the
 * development environment): this is the highest-risk piece of the whole
 * project. Simplifications assumed, each a potential point of failure:
 *   - Gardner with 2-point linear interpolation and an approximation for
 *     the "mid sample" (midpoint between the last two decided chips,
 *     instead of an independent interpolation at -sps/2) — valid near
 *     lock, but less accurate than a reference implementation.
 *   - Block sync acquisition anchored only on offset A (requires the A->B
 *     sequence confirmed at +26 bits) instead of searching all 5 offsets
 *     in parallel — simpler, somewhat slower to lock.
 *   - Ambiguity of which chip of the biphase pair comes "first": corrected
 *     by a fallback (flips the assumed parity if it goes too long without
 *     locking block sync), not resolved analytically.
 *   - No burst error correction (CRC's correction capability) — groups
 *     with an error are simply discarded.
 *   - RDS character set (G0/G1/G2) not mapped — PS/RadioText are stored as
 *     raw bytes, correct for stations that only use basic ASCII (most of
 *     them), not for the special characters in the full RDS table.
 * Loop gains (Gardner, Costas) and the 57kHz filter cutoff are
 * starting-point estimates, same warning category as dsp/fm_stereo_pilot.h.
 */

typedef struct rds_decoder rds_decoder_t;

rds_decoder_t *rds_decoder_create(float mpx_sample_rate_hz);
void rds_decoder_destroy(rds_decoder_t *d);

/* Processes `count` samples of the raw MPX (audio_pre, same buffer that
 * feeds fm_stereo_pilot_process) together with the 3rd-harmonic references
 * cos3wt/sin3wt (same PLL, same `count` size — see
 * fm_stereo_pilot_process). Should only be called when the stereo pilot is
 * locked (RDS is coherent with the pilot by definition of the standard;
 * without lock there is no valid phase reference to demodulate RDS). */
void rds_decoder_process(rds_decoder_t *d, const float *mpx, const float *cos3wt, const float *sin3wt, size_t count);

typedef struct {
    uint16_t pi_code;
    uint8_t pty;
    int32_t tp;
    int32_t ta;
    char ps[9];         /* 8 chars + NUL */
    char radiotext[65]; /* 64 chars + NUL */
    uint32_t generation; /* incremented whenever ps/radiotext actually change */
    uint32_t valid_group_count;
    int32_t sync_locked;
} rds_snapshot_t;

/* Thread-safe copy of the current decoded state (caller doesn't need to
 * deal with the decoder's internal locks — synchronization with the
 * shim_rds_info_t exposed to Dart is done in rtlsdr_shim.c, but this
 * function itself is safe to call from the same thread that runs
 * rds_decoder_process, which is the only intended use). */
void rds_decoder_snapshot(const rds_decoder_t *d, rds_snapshot_t *out);

#ifdef __cplusplus
}
#endif

#endif
