#ifndef RTLSDR_SHIM_H
#define RTLSDR_SHIM_H

#include <stdint.h>

/*
 * Public API of the native lib, called both by Dart FFI (direct dlsym,
 * hence extern "C" with no name mangling) and by jni_bridge.cpp.
 *
 * shim_open_with_fd() must only be called from JNI (jni_bridge.cpp), since
 * only the Kotlin side (UsbManager/UsbDeviceConnection) can obtain a valid
 * USB file descriptor with permission granted.
 *
 * Milestone 4: demodulation modes (WFM/NFM/AM), gain and squelch. Spectrum
 * arrives in Milestone 5.
 */

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    SHIM_OK                     = 0,
    SHIM_ERR_ALREADY_OPEN       = -1,
    SHIM_ERR_USB_WRAP_FAILED    = -2,
    SHIM_ERR_RTLSDR_INIT_FAILED = -3,
    SHIM_ERR_NOT_OPEN           = -4,
    SHIM_ERR_INVALID_ARG        = -5,
    SHIM_ERR_ALREADY_STREAMING  = -6,
    SHIM_ERR_NOT_STREAMING      = -7,
    SHIM_ERR_THREAD_FAILED      = -8,
    SHIM_ERR_RECORDING_ACTIVE   = -9,  /* already recording */
    SHIM_ERR_NOT_RECORDING      = -10, /* shim_stop_recording with no active recording */
    SHIM_ERR_RECORDING_OPEN_FAILED = -11,
} shim_status_t;

typedef enum {
    DEMOD_WFM = 0,
    DEMOD_NFM = 1,
    DEMOD_AM  = 2,
} demod_mode_t;

/* ---- Lifecycle ------------------------------------------------------- */

int32_t shim_open_with_fd(int32_t usb_fd, int32_t vendor_id, int32_t product_id);
int32_t shim_close(void);
int32_t shim_is_open(void);

/* ---- Tuning ------------------------------------------------------------ */

int32_t shim_set_frequency_hz(uint32_t freq_hz);
uint32_t shim_get_frequency_hz(void);
int32_t shim_set_sample_rate_hz(uint32_t rate_hz);
uint32_t shim_get_sample_rate_hz(void);

/* ---- Gain ----------------------------------------------------------------
 * Gain values in tenths of a dB (librtlsdr's own convention), e.g.
 * 40 = 4.0 dB. */

int32_t shim_set_gain_mode(int32_t auto_gain); /* 1 = automatic AGC, 0 = manual */
/* Sets the manual gain (also automatically switches to manual mode). */
int32_t shim_set_gain_tenth_db(int32_t gain_tenths_db);
/* Fills out_tenths_db (up to max_count) with the gains supported by the
 * tuner; returns how many were written (or < 0 on error). */
int32_t shim_get_gain_list(int32_t *out_tenths_db, int32_t max_count);

/* ---- Demodulation / squelch --------------------------------------------
 * Changing the mode only takes effect on the next shim_start_streaming()
 * (the DSP thread reads the mode once at startup) — switching modes while
 * streaming is active requires stopping and starting again. Squelch only
 * applies to NFM/AM; WFM ignores it (commercial broadcast radio wouldn't
 * have squelch, it's always "open"). */

int32_t shim_set_demod_mode(int32_t mode /* demod_mode_t */);
int32_t shim_get_demod_mode(void);
int32_t shim_set_squelch_threshold_db(float threshold_db);

/* ---- Stereo (WFM) --------------------------------------------------------
 * Unlike demod_mode, applied live (the DSP thread reads the atomic every
 * block) — no need to stop/restart streaming to switch. Doesn't force a
 * mono stream on the hardware/Oboe when off: it only controls the L/R
 * blend (see rtlsdr_shim.c), the output stream stays stereo in WFM
 * (identical channels = perceived mono) to avoid reopening Oboe on every
 * toggle. `stereo_locked` in shim_stats_t reflects whether the 19kHz
 * pilot is detected in the signal, independent of this toggle. */
int32_t shim_set_stereo_enabled(int32_t enabled);

/* ---- RDS (WFM) -------------------------------------------------------------
 * Only decodes with the stereo pilot locked (RDS is coherent with the
 * pilot by definition of the standard — see dsp/rds_decoder.h). Applied
 * live, like the stereo toggle. `sync_locked` here is the RDS BLOCK sync
 * (26 bits, CRC/offset word) — independent of `stereo_locked` in
 * shim_stats_t (19kHz pilot), though it depends on it to even start
 * trying. */
int32_t shim_set_rds_enabled(int32_t enabled);

typedef struct {
    uint16_t pi_code;
    uint8_t  pty;
    int32_t  tp;
    int32_t  ta;
    char     ps[9];         /* 8 chars + NUL, filled in progressively */
    char     radiotext[65]; /* 64 chars + NUL, filled in progressively */
    uint32_t generation;    /* incremented whenever ps/radiotext actually change —
                              * Dart can use this to avoid diffing strings */
    uint32_t valid_group_count;
    int32_t  sync_locked;
} shim_rds_info_t;

int32_t shim_get_rds_info(shim_rds_info_t *out);

/* ---- Streaming -------------------------------------------------------- */

int32_t shim_start_streaming(void);
int32_t shim_stop_streaming(void);
int32_t shim_is_streaming(void);

/* ---- Telemetry (Dart polls periodically) ------------------------------- */

typedef struct {
    uint64_t iq_bytes_received;
    uint32_t ring_overflow_count;
    float    rf_level_dbfs;
    float    audio_level_dbfs;
    int32_t  squelch_open;
    uint64_t recording_bytes_written; /* 0 if not recording */
    int32_t  stereo_locked;           /* 19kHz pilot detected (only meaningful in WFM) */
    float    pilot_level;             /* pilot amplitude (arbitrary unit, only useful relatively) */
} shim_stats_t;

int32_t shim_get_stats(shim_stats_t *out);

/* ---- Recording -------------------------------------------------------------
 * Records the same PCM that already goes to the speaker (tapped right
 * before pcm_ring's ring_buffer_write, inside the DSP thread) directly to
 * a WAV file at `file_path` (full path, the parent directory must already
 * exist — the Dart caller's responsibility, which has access to
 * path_provider). Requires active streaming (shim_start_streaming already
 * called). Stopping streaming automatically finalizes an in-progress
 * recording (closes the WAV with corrected sizes) — no file is left
 * behind with a zeroed header. */
int32_t shim_start_recording(const char *file_path);
int32_t shim_stop_recording(void);
int32_t shim_is_recording(void);

/* ---- Spectrum (Dart polls at ~20-30fps for the waterfall) --------------
 * Snapshot of the whole captured band (not the demodulator's narrow
 * channel), computed over raw pre-decimation IQ. out_mag_db[0] = lower
 * edge of the band, out_mag_db[num_bins-1] = upper edge — ready to draw
 * directly. Returns num_bins on success, 0 if not streaming (no new data
 * yet). num_bins must be <= 1024. */
int32_t shim_get_spectrum_db(float *out_mag_db, int32_t num_bins);

#ifdef __cplusplus
}
#endif

#endif
