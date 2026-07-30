#include "rtlsdr_shim.h"

#include <android/log.h>
#include <errno.h>
#include <libusb.h>
#include <math.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "audio/audio_sink.h"
#include "dsp/deemphasis.h"
#include "dsp/demod_am.h"
#include "dsp/demod_fm.h"
#include "dsp/demod_ssb.h"
#include "dsp/fir_decimator.h"
#include "dsp/fm_stereo_pilot.h"
#include "dsp/rds_decoder.h"
#include "dsp/ring_buffer.h"
#include "dsp/spectrum_fft.h"
#include "dsp/wav_writer.h"
#include "rtl-sdr.h"
#include "rtlsdr_open_fd.h"

#define LOG_TAG "rtlsdr_shim"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

/* 4 MiB ~= 1s of margin at 2.048 Msps (2 bytes/sample) before the DSP
 * thread needs to keep up. Must be a power of 2 (see ring_buffer.h). */
#define IQ_RING_CAPACITY (4u * 1024u * 1024u)
/* 256 KiB ~= 2s of margin for 16-bit stereo PCM at 32kHz (doubled from the
 * original 128 KiB, mono-only value, to cover the WFM stereo worst case —
 * extra headroom in mono NFM/AM is harmless). Margin against scheduling
 * jitter between the DSP thread and Oboe's audio callback. */
#define PCM_RING_CAPACITY (256u * 1024u)
#define DEFAULT_SAMPLE_RATE_HZ 1024000u
#define DEFAULT_FREQUENCY_HZ 100000000u /* 100.0 MHz, within the commercial FM band */
#define DEFAULT_SQUELCH_THRESHOLD_DB (-40.0f)

/* DSP pipeline: two-stage decimation, parameterized by mode — raw IQ ->
 * channel band (integer decimation from the capture rate) -> demodulator
 * -> final audio (decimated again, now the real post-demodulation
 * signal). WFM needs a wide channel band (~200kHz, deviation up to 75kHz);
 * NFM/AM are much narrower (~10-25kHz) so they decimate more right in the
 * first stage — less adjacent-band noise entering the demodulator. */
#define IQ_STAGE_TARGET_WFM_HZ 256000u
#define IQ_STAGE_TARGET_NARROW_HZ 32000u /* NFM and AM */
#define AUDIO_TARGET_HZ 32000u
#define FIR_NUM_TAPS 63
#define DSP_READ_CHUNK_BYTES 4096u
#define WORK_CAPACITY (DSP_READ_CHUNK_BYTES / 2u)

#define WFM_MAX_DEVIATION_HZ 75000.0f
#define WFM_DEEMPHASIS_TAU_US 50.0f /* Europe/most of the world; US/Korea use 75 */
#define NFM_MAX_DEVIATION_HZ 5000.0f
#define SQUELCH_HYSTERESIS_DB 2.0f

/* Time constant of the mono<->stereo blend (smooth ramp when gaining/losing
 * pilot lock, avoids an abrupt cut — see dsp_thread_main). Starting-point
 * estimate (~150ms), not validated on real hardware. */
#define STEREO_BLEND_TAU_S 0.15f

/* Spectrum: FFT over raw IQ (whole band, pre-decimation), throttled to
 * ~20Hz (the DSP thread runs at ~500 iterations/s with the current read
 * chunk). 1024 bins is plenty of granularity for a waterfall on a phone
 * screen; shim_get_spectrum_db downsamples if the caller asks for fewer. */
#define SPECTRUM_FFT_SIZE 1024
#define SPECTRUM_UPDATE_INTERVAL_ITERS 25

typedef struct {
    pthread_mutex_t lock;

    _Atomic int is_open;
    _Atomic int is_streaming;
    _Atomic int stop_requested;

    libusb_context *usb_ctx;
    libusb_device_handle *usb_devh;
    rtlsdr_dev_t *rtl_dev;

    uint32_t frequency_hz;
    uint32_t sample_rate_hz;

    _Atomic int demod_mode; /* demod_mode_t */
    _Atomic float squelch_threshold_db;

    pthread_t usb_thread;
    pthread_t dsp_thread;

    ring_buffer_t iq_ring;
    ring_buffer_t pcm_ring;

    _Atomic uint64_t iq_bytes_received;
    _Atomic uint32_t ring_overflow_count;
    _Atomic float audio_level_dbfs;
    _Atomic float rf_level_dbfs;
    _Atomic int squelch_open;

    /* Stereo (WFM): stereo_enabled is the user's toggle (read live, no
     * need to restart streaming — unlike demod_mode), the other two are
     * read-only for Dart, written by dsp_thread every block.
     * audio_channel_count is read by pcm_pull_callback (Oboe thread) to
     * know how many samples per frame to pull from pcm_ring — 1 or 2,
     * decided by dsp_thread at startup (always 2 whenever mode==WFM, even
     * without lock/with stereo_enabled=0, to avoid reopening Oboe on every
     * toggle; see rtlsdr_shim.h). */
    _Atomic int stereo_enabled;
    _Atomic int stereo_locked;
    _Atomic float pilot_level;
    _Atomic int audio_channel_count;

    /* RDS (WFM) — snapshot protected by rds_lock, same pattern as the
     * spectrum (spectrum_lock/spectrum_snapshot): PI/PS/RadioText are
     * variable-length, don't fit in a plain _Atomic. rds_enabled is the
     * user's toggle, applied live. */
    _Atomic int rds_enabled;
    pthread_mutex_t rds_lock;
    rds_snapshot_t rds_snapshot;

    pthread_mutex_t spectrum_lock;
    float spectrum_snapshot[SPECTRUM_FFT_SIZE];
    _Atomic int spectrum_valid;

    /* Recording: protected by record_lock (not by the atomics alone) —
     * shim_stop_recording can run concurrently with dsp_thread's write,
     * and without a lock there would be a use-after-free window between
     * "recording_active is still 1" and the actual wav_writer_write (see
     * stop_recording_if_active()). */
    pthread_mutex_t record_lock;
    wav_writer_t *record_writer;
    _Atomic int recording_active;
    _Atomic uint64_t recording_bytes_written;
} shim_state_t;

static shim_state_t g_state = {
    .lock = PTHREAD_MUTEX_INITIALIZER,
    .spectrum_lock = PTHREAD_MUTEX_INITIALIZER,
    .record_lock = PTHREAD_MUTEX_INITIALIZER,
    .rds_lock = PTHREAD_MUTEX_INITIALIZER,
};

/* ---- USB reader callback (called from inside libusb_handle_events, on
 * usb_thread) — needs to be fast: just copies into the ring and counts
 * bytes, no processing here. */
static void iq_callback(unsigned char *buf, uint32_t len, void *ctx) {
    (void)ctx;
    if (atomic_load_explicit(&g_state.stop_requested, memory_order_relaxed)) {
        return;
    }

    atomic_fetch_add_explicit(&g_state.iq_bytes_received, len, memory_order_relaxed);

    size_t written = ring_buffer_write(&g_state.iq_ring, buf, len);
    if (written < len) {
        atomic_fetch_add_explicit(&g_state.ring_overflow_count, 1, memory_order_relaxed);
    }
}

static void *usb_thread_main(void *arg) {
    (void)arg;
    rtlsdr_dev_t *rtl_dev = g_state.rtl_dev;

    rtlsdr_reset_buffer(rtl_dev);

    /* Blocks until rtlsdr_cancel_async() is called (from another thread —
     * same pattern used by upstream rtl_tcp.c: read_async runs on one
     * thread while a command from another thread cancels it). */
    int r = rtlsdr_read_async(rtl_dev, iq_callback, NULL, 0, 0);
    if (r != 0) {
        LOGE("rtlsdr_read_async exited with error %d", r);
    }
    return NULL;
}

/* Called by Oboe's audio thread (audio_sink_oboe.cpp) — only pulls from
 * the PCM ring, never blocks. `num_frames`/return value are in FRAMES
 * (see audio_sink.h) — multiplies/divides by audio_channel_count to
 * convert to/from the interleaved int16 samples actually stored in the
 * ring. */
static size_t pcm_pull_callback(int16_t *out, size_t num_frames, void *user_data) {
    (void)user_data;
    int channels = atomic_load_explicit(&g_state.audio_channel_count, memory_order_relaxed);
    if (channels < 1) {
        channels = 1;
    }
    size_t bytes_wanted = num_frames * (size_t)channels * sizeof(int16_t);
    size_t bytes_read = ring_buffer_read(&g_state.pcm_ring, (uint8_t *)out, bytes_wanted);
    return bytes_read / ((size_t)channels * sizeof(int16_t));
}

static inline float clamp_unit(float x) {
    if (x > 1.0f) return 1.0f;
    if (x < -1.0f) return -1.0f;
    return x;
}

static float compute_rms_dbfs(const float *i, const float *q, size_t count) {
    if (count == 0) {
        return -120.0f;
    }
    float sum_sq = 0.0f;
    for (size_t n = 0; n < count; n++) {
        sum_sq += i[n] * i[n] + q[n] * q[n];
    }
    float rms = sqrtf(sum_sq / (float)count);
    return (rms > 1e-9f) ? 20.0f * log10f(rms) : -120.0f;
}

/* DSP thread: consumes raw IQ from the ring, decimation + demodulator
 * (WFM/NFM/AM/USB/LSB, per the mode read at startup — switching modes
 * requires stopping and restarting streaming) + squelch (NFM/AM/USB/LSB) +
 * audio decimation, writes PCM to the audio ring consumed by Oboe's
 * callback. */
static void *dsp_thread_main(void *arg) {
    (void)arg;

    uint32_t input_rate = g_state.sample_rate_hz;
    demod_mode_t mode = (demod_mode_t)atomic_load_explicit(&g_state.demod_mode, memory_order_relaxed);
    int squelch_enabled = (mode != DEMOD_WFM);

    uint32_t iq_stage_target_hz = (mode == DEMOD_WFM) ? IQ_STAGE_TARGET_WFM_HZ : IQ_STAGE_TARGET_NARROW_HZ;

    int iq_decim = (int)(input_rate / iq_stage_target_hz);
    if (iq_decim < 1) {
        iq_decim = 1;
    }
    uint32_t iq_stage_rate = input_rate / (uint32_t)iq_decim;

    int audio_decim = (int)(iq_stage_rate / AUDIO_TARGET_HZ);
    if (audio_decim < 1) {
        audio_decim = 1;
    }
    uint32_t audio_rate = iq_stage_rate / (uint32_t)audio_decim;

    /* WFM always opens Oboe in stereo (2 channels), even without pilot
     * lock or with the user preferring mono — in that case both channels
     * carry identical audio (blend=0, see main loop). This avoids
     * closing/reopening the Oboe stream on every shim_set_stereo_enabled
     * or every time the pilot locks/unlocks, which only flips the
     * stereo_enabled/stereo_locked atomic live. */
    int channel_count = (mode == DEMOD_WFM) ? 2 : 1;
    atomic_store_explicit(&g_state.audio_channel_count, channel_count, memory_order_relaxed);

    fir_decimator_t iq_stage;
    fir_decimator_t audio_stage;
    if (fir_decimator_init(&iq_stage, iq_decim, FIR_NUM_TAPS, 0.9f / (float)iq_decim, /*complex_mode=*/1) != 0) {
        LOGE("fir_decimator_init (IQ) failed");
        return NULL;
    }
    /* In WFM, audio_stage decimates L and R in lockstep (complex_mode=1
     * treated as two parallel real filters, not an actual IQ rotation —
     * see dsp/fir_decimator.h). NFM/AM keep decimating a single real
     * signal, exactly as before. */
    if (fir_decimator_init(&audio_stage, audio_decim, FIR_NUM_TAPS, 0.9f / (float)audio_decim,
                            /*complex_mode=*/(mode == DEMOD_WFM) ? 1 : 0) != 0) {
        LOGE("fir_decimator_init (audio) failed");
        fir_decimator_destroy(&iq_stage);
        return NULL;
    }

    fm_demod_t fm_demod;
    am_demod_t am_demod;
    ssb_demod_t ssb_demod;
    fm_stereo_pilot_t stereo_pilot;
    rds_decoder_t *rds_decoder = NULL;
    deemphasis_t deemph_l;
    deemphasis_t deemph_r;
    float blend = 0.0f;      /* 0 = mono (L=R=L+R), 1 = full stereo — see main loop */
    float blend_alpha = 0.0f;
    switch (mode) {
        case DEMOD_NFM:
            fm_demod_init(&fm_demod, (float)iq_stage_rate, NFM_MAX_DEVIATION_HZ, /*deemphasis=*/0.0f);
            break;
        case DEMOD_AM:
            am_demod_init(&am_demod);
            break;
        case DEMOD_USB:
        case DEMOD_LSB:
            if (ssb_demod_init(&ssb_demod, /*sideband=*/(mode == DEMOD_LSB) ? 1 : 0) != 0) {
                LOGE("ssb_demod_init failed");
            }
            break;
        case DEMOD_WFM:
        default:
            /* De-emphasis OFF here (0.0f) — unlike before. The raw MPX
             * needs to survive intact (19kHz pilot, 38kHz subcarrier)
             * until after the L/R demux; the actual de-emphasis runs
             * afterward, per channel, via deemph_l/deemph_r (see below and
             * dsp/deemphasis.h). */
            fm_demod_init(&fm_demod, (float)iq_stage_rate, WFM_MAX_DEVIATION_HZ, /*deemphasis=*/0.0f);
            fm_stereo_pilot_init(&stereo_pilot, (float)iq_stage_rate);
            rds_decoder = rds_decoder_create((float)iq_stage_rate);
            if (!rds_decoder) {
                LOGE("rds_decoder_create failed — RDS will have no data this session");
            }
            deemphasis_init(&deemph_l, (float)audio_rate, WFM_DEEMPHASIS_TAU_US);
            deemphasis_init(&deemph_r, (float)audio_rate, WFM_DEEMPHASIS_TAU_US);
            {
                float dt = 1.0f / (float)iq_stage_rate;
                blend_alpha = dt / (STEREO_BLEND_TAU_S + dt);
            }
            break;
    }

    /* Reopening the Oboe stream right after closing the previous one
     * (e.g. automatic restart when switching modes in
     * shim_set_demod_mode/RadioController) can fail transiently — the
     * audio HAL sometimes hasn't finished releasing the previous stream's
     * resources yet. Without a retry, streaming kept running normally
     * (IQ, RF, squelch) but with no audio at all, silently. */
    int audio_ready = 0;
    for (int attempt = 1; attempt <= 3 && !audio_ready; attempt++) {
        if (audio_sink_start(audio_rate, channel_count, pcm_pull_callback, NULL) == 0) {
            audio_ready = 1;
        } else {
            LOGE("audio_sink_start failed (attempt %d/3, rate %u Hz, %d channels)", attempt, audio_rate,
                 channel_count);
            if (attempt < 3) {
                usleep(100000);
            }
        }
    }
    if (!audio_ready) {
        LOGE("audio_sink_start gave up after 3 attempts — streaming will continue without audio");
    }

    LOGI("DSP pipeline: mode %d, input %u Hz -> IQ decim %d -> %u Hz -> audio decim %d -> %u Hz (%d channel(s))",
         (int)mode, input_rate, iq_decim, iq_stage_rate, audio_decim, audio_rate, channel_count);

    spectrum_fft_t spectrum;
    int spectrum_ok = (spectrum_fft_init(&spectrum, SPECTRUM_FFT_SIZE) == 0);
    if (!spectrum_ok) {
        LOGE("spectrum_fft_init failed — waterfall will have no data this session");
    }
    int spectrum_counter = 0;
    float spectrum_out[SPECTRUM_FFT_SIZE];

    uint8_t raw[DSP_READ_CHUNK_BYTES];
    float iq_i[WORK_CAPACITY];
    float iq_q[WORK_CAPACITY];
    float stage1_i[WORK_CAPACITY];
    float stage1_q[WORK_CAPACITY];
    float audio_pre[WORK_CAPACITY]; /* raw MPX (WFM) or demodulated audio (NFM/AM); reused as L in-place in WFM */
    float audio_out[WORK_CAPACITY]; /* decimated mono audio, or decimated L in WFM */
    int16_t pcm_out[2 * WORK_CAPACITY]; /* mono: audio_count samples; stereo: audio_count*2 interleaved L,R,L,R... */

    /* Only used in WFM — see switch(mode) above where stereo_pilot is
     * initialized. cos2wt: coherent 38kHz reference (2nd harmonic of the
     * pilot) for the L-R demux. mpx_diff: baseband L-R, reused as R
     * in-place (same technique as audio_pre becoming L). audio_out_r: R
     * post-decimation (counterpart of audio_out, which becomes L
     * post-decimation in WFM). */
    float cos2wt[WORK_CAPACITY];
    float mpx_diff[WORK_CAPACITY];
    float audio_out_r[WORK_CAPACITY];

    /* Only used when rds_decoder != NULL — 3rd harmonic of the pilot
     * (57kHz), same PLL as cos2wt, for RDS downconversion (see
     * dsp/rds_decoder.h). */
    float cos3wt[WORK_CAPACITY];
    float sin3wt[WORK_CAPACITY];

    int squelch_was_open = 1;

    while (!atomic_load_explicit(&g_state.stop_requested, memory_order_relaxed)) {
        size_t n = ring_buffer_read(&g_state.iq_ring, raw, sizeof(raw));
        if (n == 0) {
            usleep(2000);
            continue;
        }

        size_t pairs = n / 2;
        for (size_t k = 0; k < pairs; k++) {
            /* RTL2832U delivers 8-bit unsigned offset-binary IQ (0..255,
             * centered at ~127.5) — normalizes to -1..1. */
            iq_i[k] = ((float)raw[2 * k] - 127.5f) / 127.5f;
            iq_q[k] = ((float)raw[2 * k + 1] - 127.5f) / 127.5f;
        }

        if (spectrum_ok && pairs >= (size_t)SPECTRUM_FFT_SIZE) {
            spectrum_counter++;
            if (spectrum_counter >= SPECTRUM_UPDATE_INTERVAL_ITERS) {
                spectrum_counter = 0;
                /* uses the most recent samples of the block just read */
                size_t offset = pairs - (size_t)SPECTRUM_FFT_SIZE;
                spectrum_fft_process(&spectrum, &iq_i[offset], &iq_q[offset], spectrum_out);
                pthread_mutex_lock(&g_state.spectrum_lock);
                memcpy(g_state.spectrum_snapshot, spectrum_out, sizeof(spectrum_out));
                pthread_mutex_unlock(&g_state.spectrum_lock);
                atomic_store_explicit(&g_state.spectrum_valid, 1, memory_order_relaxed);
            }
        }

        size_t stage1_count = fir_decimator_process(&iq_stage, iq_i, iq_q, pairs, stage1_i, stage1_q, WORK_CAPACITY);
        if (stage1_count == 0) {
            continue;
        }

        float rf_dbfs = compute_rms_dbfs(stage1_i, stage1_q, stage1_count);
        atomic_store_explicit(&g_state.rf_level_dbfs, rf_dbfs, memory_order_relaxed);

        int squelch_open = 1;
        if (squelch_enabled) {
            float threshold = atomic_load_explicit(&g_state.squelch_threshold_db, memory_order_relaxed);
            float effective_threshold = squelch_was_open ? (threshold - SQUELCH_HYSTERESIS_DB)
                                                           : (threshold + SQUELCH_HYSTERESIS_DB);
            squelch_open = (rf_dbfs >= effective_threshold);
            squelch_was_open = squelch_open;
        }
        atomic_store_explicit(&g_state.squelch_open, squelch_open, memory_order_relaxed);

        size_t audio_count;

        if (mode == DEMOD_AM) {
            am_demod_process(&am_demod, stage1_i, stage1_q, stage1_count, audio_pre);
            audio_count =
                fir_decimator_process(&audio_stage, audio_pre, NULL, stage1_count, audio_out, NULL, WORK_CAPACITY);
        } else if (mode == DEMOD_NFM) {
            fm_demod_process(&fm_demod, stage1_i, stage1_q, stage1_count, audio_pre);
            audio_count =
                fir_decimator_process(&audio_stage, audio_pre, NULL, stage1_count, audio_out, NULL, WORK_CAPACITY);
        } else if (mode == DEMOD_USB || mode == DEMOD_LSB) {
            ssb_demod_process(&ssb_demod, stage1_i, stage1_q, stage1_count, audio_pre);
            audio_count =
                fir_decimator_process(&audio_stage, audio_pre, NULL, stage1_count, audio_out, NULL, WORK_CAPACITY);
        } else {
            /* DEMOD_WFM: audio_pre receives the raw MPX (no de-emphasis,
             * see fm_demod_init above) — 19kHz pilot + L+R (0-15kHz) +
             * L-R around 38kHz still intact. */
            fm_demod_process(&fm_demod, stage1_i, stage1_q, stage1_count, audio_pre);

            fm_stereo_pilot_process(&stereo_pilot, audio_pre, stage1_count, cos2wt, NULL, cos3wt, sin3wt);
            int locked = fm_stereo_pilot_locked(&stereo_pilot);
            atomic_store_explicit(&g_state.stereo_locked, locked, memory_order_relaxed);
            atomic_store_explicit(&g_state.pilot_level, fm_stereo_pilot_amplitude(&stereo_pilot),
                                   memory_order_relaxed);

            /* RDS: needs to run HERE, with audio_pre still intact (raw
             * MPX) — the blend loop right below reuses audio_pre in-place
             * as L, which would destroy RDS's input if called afterward.
             * Only decodes with the pilot locked (RDS is coherent with the
             * pilot by definition of the standard). */
            if (rds_decoder) {
                int rds_enabled = atomic_load_explicit(&g_state.rds_enabled, memory_order_relaxed);
                if (locked && rds_enabled) {
                    rds_decoder_process(rds_decoder, audio_pre, cos3wt, sin3wt, stage1_count);
                    rds_snapshot_t snap;
                    rds_decoder_snapshot(rds_decoder, &snap);
                    pthread_mutex_lock(&g_state.rds_lock);
                    g_state.rds_snapshot = snap;
                    pthread_mutex_unlock(&g_state.rds_lock);
                } else {
                    /* No pilot lock (or disabled by the user): doesn't
                     * feed the decoder, only reports sync_locked=0 —
                     * keeps the already-decoded PI/PS/RadioText as they
                     * were (a brief lock drop shouldn't wipe the station
                     * name off the screen). */
                    pthread_mutex_lock(&g_state.rds_lock);
                    g_state.rds_snapshot.sync_locked = 0;
                    pthread_mutex_unlock(&g_state.rds_lock);
                }
            }

            int stereo_enabled = atomic_load_explicit(&g_state.stereo_enabled, memory_order_relaxed);
            float target_blend = (locked && stereo_enabled) ? 1.0f : 0.0f;

            /* Per-sample L/R demux + smooth mono<->stereo ramp (blend,
             * one-pole same as de-emphasis) — avoids an abrupt cut when
             * gaining/losing lock. blend=0 reproduces exactly the old mono
             * pipeline (L=R=L+R, no 6dB loss); blend=1 is the classic
             * demux L=(Σ+Δ)/2, R=(Σ-Δ)/2. audio_pre/mpx_diff are reused
             * in-place as L/R — safe because index k is read before being
             * overwritten, with no dependency between k's. */
            for (size_t k = 0; k < stage1_count; k++) {
                blend += blend_alpha * (target_blend - blend);
                float lr_sum = audio_pre[k];
                float lr_diff = 2.0f * lr_sum * cos2wt[k];
                float l = lr_sum * (1.0f - 0.5f * blend) + 0.5f * blend * lr_diff;
                float r = lr_sum * (1.0f - 0.5f * blend) - 0.5f * blend * lr_diff;
                audio_pre[k] = l;
                mpx_diff[k] = r;
            }

            audio_count = fir_decimator_process(&audio_stage, audio_pre, mpx_diff, stage1_count, audio_out,
                                                 audio_out_r, WORK_CAPACITY);
            if (audio_count > 0) {
                deemphasis_process(&deemph_l, audio_out, audio_count, audio_out);
                deemphasis_process(&deemph_r, audio_out_r, audio_count, audio_out_r);
            }
        }

        if (audio_count == 0) {
            continue;
        }

        size_t pcm_sample_count = audio_count * (size_t)channel_count;

        if (!squelch_open) {
            memset(pcm_out, 0, pcm_sample_count * sizeof(int16_t));
            atomic_store_explicit(&g_state.audio_level_dbfs, -90.0f, memory_order_relaxed);
        } else {
            float peak = 0.0f;
            if (channel_count == 2) {
                for (size_t k = 0; k < audio_count; k++) {
                    float l = clamp_unit(audio_out[k]);
                    float r = clamp_unit(audio_out_r[k]);
                    pcm_out[2 * k] = (int16_t)(l * 32767.0f);
                    pcm_out[2 * k + 1] = (int16_t)(r * 32767.0f);
                    float abs_l = fabsf(l);
                    float abs_r = fabsf(r);
                    if (abs_l > peak) peak = abs_l;
                    if (abs_r > peak) peak = abs_r;
                }
            } else {
                for (size_t k = 0; k < audio_count; k++) {
                    float sample = clamp_unit(audio_out[k]);
                    pcm_out[k] = (int16_t)(sample * 32767.0f);
                    float abs_sample = fabsf(sample);
                    if (abs_sample > peak) peak = abs_sample;
                }
            }
            float dbfs = (peak > 1e-6f) ? 20.0f * log10f(peak) : -90.0f;
            atomic_store_explicit(&g_state.audio_level_dbfs, dbfs, memory_order_relaxed);
        }

        ring_buffer_write(&g_state.pcm_ring, (const uint8_t *)pcm_out, pcm_sample_count * sizeof(int16_t));

        /* Records the same PCM that just went to pcm_ring (a tap, not a
         * separate ring buffer or its own thread — see rtlsdr_shim.h). The
         * atomic check outside the lock is just an optimization to avoid
         * paying for a mutex every iteration when not recording; the
         * correctness against the race with shim_stop_recording comes
         * from the re-check of record_writer != NULL already inside the
         * lock. The wav_writer's channel count was fixed in
         * shim_start_recording by reading audio_channel_count at that
         * moment — consistent here because the UI (device_screen.dart)
         * always stops an in-progress recording before switching modes. */
        if (atomic_load_explicit(&g_state.recording_active, memory_order_relaxed)) {
            pthread_mutex_lock(&g_state.record_lock);
            if (g_state.record_writer && wav_writer_write(g_state.record_writer, pcm_out, audio_count) == 0) {
                atomic_fetch_add_explicit(&g_state.recording_bytes_written, pcm_sample_count * sizeof(int16_t),
                                           memory_order_relaxed);
            }
            pthread_mutex_unlock(&g_state.record_lock);
        }
    }

    audio_sink_stop();
    if (rds_decoder) {
        rds_decoder_destroy(rds_decoder);
    }
    if (mode == DEMOD_USB || mode == DEMOD_LSB) {
        ssb_demod_destroy(&ssb_demod);
    }
    fir_decimator_destroy(&iq_stage);
    fir_decimator_destroy(&audio_stage);
    if (spectrum_ok) {
        spectrum_fft_destroy(&spectrum);
    }
    atomic_store_explicit(&g_state.spectrum_valid, 0, memory_order_relaxed);

    while (ring_buffer_read(&g_state.iq_ring, raw, sizeof(raw)) > 0) {
        /* drains the remainder so no residual overflow is left after stop */
    }
    return NULL;
}

int32_t shim_open_with_fd(int32_t usb_fd, int32_t vendor_id, int32_t product_id) {
    (void)vendor_id;  /* reserved for future per-dongle differences */
    (void)product_id;

    pthread_mutex_lock(&g_state.lock);
    if (atomic_load(&g_state.is_open)) {
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_ALREADY_OPEN;
    }

    libusb_context *ctx = NULL;
    struct libusb_init_option opts[1];
    opts[0].option = LIBUSB_OPTION_NO_DEVICE_DISCOVERY;
    opts[0].value.ival = 0;
    int r = libusb_init_context(&ctx, opts, 1);
    if (r != LIBUSB_SUCCESS) {
        LOGE("libusb_init_context failed: %d", r);
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_USB_WRAP_FAILED;
    }

    libusb_device_handle *devh = NULL;
    r = libusb_wrap_sys_device(ctx, (intptr_t)usb_fd, &devh);
    if (r != LIBUSB_SUCCESS || devh == NULL) {
        LOGE("libusb_wrap_sys_device failed: %d", r);
        libusb_exit(ctx);
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_USB_WRAP_FAILED;
    }

    rtlsdr_dev_t *rtl_dev = NULL;
    r = rtlsdr_open_fd(&rtl_dev, ctx, devh);
    if (r < 0) {
        /* rtlsdr_open_fd() already closes devh/ctx internally on the
         * error path (same cleanup as the original rtlsdr_open()) — don't
         * repeat it here, or it's a double-close/use-after-free. */
        LOGE("rtlsdr_open_fd failed: %d", r);
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_RTLSDR_INIT_FAILED;
    }

    if (ring_buffer_init(&g_state.iq_ring, IQ_RING_CAPACITY) != 0) {
        LOGE("ring_buffer_init (IQ) failed");
        rtlsdr_close(rtl_dev); /* closes devh + ctx + frees dev internally */
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_RTLSDR_INIT_FAILED;
    }
    if (ring_buffer_init(&g_state.pcm_ring, PCM_RING_CAPACITY) != 0) {
        LOGE("ring_buffer_init (PCM) failed");
        ring_buffer_destroy(&g_state.iq_ring);
        rtlsdr_close(rtl_dev);
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_RTLSDR_INIT_FAILED;
    }

    g_state.usb_ctx = ctx;
    g_state.usb_devh = devh;
    g_state.rtl_dev = rtl_dev;
    g_state.sample_rate_hz = DEFAULT_SAMPLE_RATE_HZ;
    g_state.frequency_hz = DEFAULT_FREQUENCY_HZ;
    atomic_store(&g_state.iq_bytes_received, 0);
    atomic_store(&g_state.ring_overflow_count, 0);
    atomic_store(&g_state.demod_mode, DEMOD_WFM);
    atomic_store(&g_state.squelch_threshold_db, DEFAULT_SQUELCH_THRESHOLD_DB);
    atomic_store(&g_state.rf_level_dbfs, -120.0f);
    atomic_store(&g_state.squelch_open, 1);
    atomic_store(&g_state.stereo_enabled, 1);
    atomic_store(&g_state.stereo_locked, 0);
    atomic_store(&g_state.pilot_level, 0.0f);
    atomic_store(&g_state.audio_channel_count, 1);
    atomic_store(&g_state.rds_enabled, 1);

    rtlsdr_set_sample_rate(rtl_dev, DEFAULT_SAMPLE_RATE_HZ);
    rtlsdr_set_center_freq(rtl_dev, DEFAULT_FREQUENCY_HZ);
    rtlsdr_set_tuner_gain_mode(rtl_dev, 0); /* automatic AGC by default until M4 */

    atomic_store(&g_state.is_open, 1);
    pthread_mutex_unlock(&g_state.lock);

    LOGI("Dongle opened successfully via fd %d", usb_fd);
    return SHIM_OK;
}

/* Closes and finalizes (fixed-up WAV header) an in-progress recording, if
 * any. Used both by shim_stop_recording() and by
 * shim_stop_streaming()/shim_close() — stopping streaming must not leave
 * a WAV with zeroed sizes behind, nor the recording_active flag stuck at
 * 1 (which would block a future shim_start_recording attempt).
 * Returns 1 if a recording was active (and was finalized), 0 otherwise. */
static int stop_recording_if_active(void) {
    pthread_mutex_lock(&g_state.record_lock);
    if (!atomic_load(&g_state.recording_active)) {
        pthread_mutex_unlock(&g_state.record_lock);
        return 0;
    }
    wav_writer_t *writer = g_state.record_writer;
    g_state.record_writer = NULL;
    atomic_store(&g_state.recording_active, 0);
    pthread_mutex_unlock(&g_state.record_lock);

    wav_writer_close(writer); /* outside the lock — fseek/fclose doesn't need to block dsp_thread */
    return 1;
}

int32_t shim_stop_streaming(void) {
    pthread_mutex_lock(&g_state.lock);
    if (!atomic_load(&g_state.is_streaming)) {
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_NOT_STREAMING;
    }
    rtlsdr_dev_t *rtl_dev = g_state.rtl_dev;
    pthread_t usb_thread = g_state.usb_thread;
    pthread_t dsp_thread = g_state.dsp_thread;
    atomic_store(&g_state.stop_requested, 1);
    pthread_mutex_unlock(&g_state.lock);

    if (rtl_dev) {
        rtlsdr_cancel_async(rtl_dev);
    }
    pthread_join(usb_thread, NULL);
    pthread_join(dsp_thread, NULL);

    pthread_mutex_lock(&g_state.lock);
    atomic_store(&g_state.is_streaming, 0);
    pthread_mutex_unlock(&g_state.lock);

    stop_recording_if_active();
    return SHIM_OK;
}

int32_t shim_close(void) {
    if (atomic_load(&g_state.is_streaming)) {
        shim_stop_streaming();
    }

    pthread_mutex_lock(&g_state.lock);
    if (!atomic_load(&g_state.is_open)) {
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_NOT_OPEN;
    }

    rtlsdr_close(g_state.rtl_dev); /* closes devh + ctx + frees dev internally */
    ring_buffer_destroy(&g_state.iq_ring);
    ring_buffer_destroy(&g_state.pcm_ring);

    g_state.rtl_dev = NULL;
    g_state.usb_ctx = NULL;
    g_state.usb_devh = NULL;
    atomic_store(&g_state.is_open, 0);

    pthread_mutex_unlock(&g_state.lock);
    LOGI("Dongle closed");
    return SHIM_OK;
}

int32_t shim_is_open(void) {
    return atomic_load(&g_state.is_open) ? 1 : 0;
}

int32_t shim_set_frequency_hz(uint32_t freq_hz) {
    pthread_mutex_lock(&g_state.lock);
    if (!atomic_load(&g_state.is_open)) {
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_NOT_OPEN;
    }
    int r = rtlsdr_set_center_freq(g_state.rtl_dev, freq_hz);
    if (r == 0) {
        g_state.frequency_hz = freq_hz;
    }
    pthread_mutex_unlock(&g_state.lock);
    return (r == 0) ? SHIM_OK : SHIM_ERR_INVALID_ARG;
}

uint32_t shim_get_frequency_hz(void) {
    pthread_mutex_lock(&g_state.lock);
    uint32_t freq = g_state.frequency_hz;
    pthread_mutex_unlock(&g_state.lock);
    return freq;
}

int32_t shim_set_sample_rate_hz(uint32_t rate_hz) {
    pthread_mutex_lock(&g_state.lock);
    if (!atomic_load(&g_state.is_open)) {
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_NOT_OPEN;
    }
    if (atomic_load(&g_state.is_streaming)) {
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_ALREADY_STREAMING;
    }
    int r = rtlsdr_set_sample_rate(g_state.rtl_dev, rate_hz);
    if (r == 0) {
        g_state.sample_rate_hz = rate_hz;
    }
    pthread_mutex_unlock(&g_state.lock);
    return (r == 0) ? SHIM_OK : SHIM_ERR_INVALID_ARG;
}

uint32_t shim_get_sample_rate_hz(void) {
    pthread_mutex_lock(&g_state.lock);
    uint32_t rate = g_state.sample_rate_hz;
    pthread_mutex_unlock(&g_state.lock);
    return rate;
}

int32_t shim_set_gain_mode(int32_t auto_gain) {
    pthread_mutex_lock(&g_state.lock);
    if (!atomic_load(&g_state.is_open)) {
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_NOT_OPEN;
    }
    int r = rtlsdr_set_tuner_gain_mode(g_state.rtl_dev, auto_gain ? 0 : 1);
    pthread_mutex_unlock(&g_state.lock);
    return (r == 0) ? SHIM_OK : SHIM_ERR_INVALID_ARG;
}

int32_t shim_set_gain_tenth_db(int32_t gain_tenths_db) {
    pthread_mutex_lock(&g_state.lock);
    if (!atomic_load(&g_state.is_open)) {
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_NOT_OPEN;
    }
    /* Setting a specific gain only makes sense in manual mode. */
    rtlsdr_set_tuner_gain_mode(g_state.rtl_dev, 1);
    int r = rtlsdr_set_tuner_gain(g_state.rtl_dev, gain_tenths_db);
    pthread_mutex_unlock(&g_state.lock);
    return (r == 0) ? SHIM_OK : SHIM_ERR_INVALID_ARG;
}

int32_t shim_get_gain_list(int32_t *out_tenths_db, int32_t max_count) {
    if (!out_tenths_db || max_count <= 0) {
        return SHIM_ERR_INVALID_ARG;
    }
    pthread_mutex_lock(&g_state.lock);
    if (!atomic_load(&g_state.is_open)) {
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_NOT_OPEN;
    }

    int count = rtlsdr_get_tuner_gains(g_state.rtl_dev, NULL);
    if (count <= 0) {
        pthread_mutex_unlock(&g_state.lock);
        return 0;
    }

    int *gains = (int *)malloc(sizeof(int) * (size_t)count);
    if (!gains) {
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_INVALID_ARG;
    }
    rtlsdr_get_tuner_gains(g_state.rtl_dev, gains);

    int32_t written = (count < max_count) ? count : max_count;
    for (int32_t i = 0; i < written; i++) {
        out_tenths_db[i] = gains[i];
    }
    free(gains);

    pthread_mutex_unlock(&g_state.lock);
    return written;
}

int32_t shim_set_demod_mode(int32_t mode) {
    if (mode != DEMOD_WFM && mode != DEMOD_NFM && mode != DEMOD_AM && mode != DEMOD_USB && mode != DEMOD_LSB) {
        return SHIM_ERR_INVALID_ARG;
    }
    atomic_store_explicit(&g_state.demod_mode, mode, memory_order_relaxed);
    return SHIM_OK;
}

int32_t shim_get_demod_mode(void) {
    return atomic_load_explicit(&g_state.demod_mode, memory_order_relaxed);
}

int32_t shim_set_squelch_threshold_db(float threshold_db) {
    atomic_store_explicit(&g_state.squelch_threshold_db, threshold_db, memory_order_relaxed);
    return SHIM_OK;
}

int32_t shim_set_stereo_enabled(int32_t enabled) {
    atomic_store_explicit(&g_state.stereo_enabled, enabled ? 1 : 0, memory_order_relaxed);
    return SHIM_OK;
}

int32_t shim_set_rds_enabled(int32_t enabled) {
    atomic_store_explicit(&g_state.rds_enabled, enabled ? 1 : 0, memory_order_relaxed);
    return SHIM_OK;
}

int32_t shim_get_rds_info(shim_rds_info_t *out) {
    if (!out) {
        return SHIM_ERR_INVALID_ARG;
    }
    pthread_mutex_lock(&g_state.rds_lock);
    out->pi_code = g_state.rds_snapshot.pi_code;
    out->pty = g_state.rds_snapshot.pty;
    out->tp = g_state.rds_snapshot.tp;
    out->ta = g_state.rds_snapshot.ta;
    memcpy(out->ps, g_state.rds_snapshot.ps, sizeof(out->ps));
    memcpy(out->radiotext, g_state.rds_snapshot.radiotext, sizeof(out->radiotext));
    out->generation = g_state.rds_snapshot.generation;
    out->valid_group_count = g_state.rds_snapshot.valid_group_count;
    out->sync_locked = g_state.rds_snapshot.sync_locked;
    pthread_mutex_unlock(&g_state.rds_lock);
    return SHIM_OK;
}

int32_t shim_start_streaming(void) {
    pthread_mutex_lock(&g_state.lock);
    if (!atomic_load(&g_state.is_open)) {
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_NOT_OPEN;
    }
    if (atomic_load(&g_state.is_streaming)) {
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_ALREADY_STREAMING;
    }

    ring_buffer_reset(&g_state.iq_ring);
    ring_buffer_reset(&g_state.pcm_ring);
    atomic_store(&g_state.iq_bytes_received, 0);
    atomic_store(&g_state.ring_overflow_count, 0);
    atomic_store(&g_state.audio_level_dbfs, -90.0f);
    atomic_store(&g_state.spectrum_valid, 0);
    atomic_store(&g_state.stop_requested, 0);

    /* Discards PI/PS/RadioText from a previous session — it shouldn't
     * survive a stop/start (switching stations, for example). */
    pthread_mutex_lock(&g_state.rds_lock);
    memset(&g_state.rds_snapshot, 0, sizeof(g_state.rds_snapshot));
    pthread_mutex_unlock(&g_state.rds_lock);

    int r = pthread_create(&g_state.dsp_thread, NULL, dsp_thread_main, NULL);
    if (r != 0) {
        LOGE("Failed to create dsp_thread: %d", r);
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_THREAD_FAILED;
    }
    r = pthread_create(&g_state.usb_thread, NULL, usb_thread_main, NULL);
    if (r != 0) {
        LOGE("Failed to create usb_thread: %d", r);
        atomic_store(&g_state.stop_requested, 1);
        pthread_join(g_state.dsp_thread, NULL);
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_THREAD_FAILED;
    }

    atomic_store(&g_state.is_streaming, 1);
    pthread_mutex_unlock(&g_state.lock);
    return SHIM_OK;
}

int32_t shim_is_streaming(void) {
    return atomic_load(&g_state.is_streaming) ? 1 : 0;
}

int32_t shim_get_stats(shim_stats_t *out) {
    if (!out) {
        return SHIM_ERR_INVALID_ARG;
    }
    out->iq_bytes_received = atomic_load_explicit(&g_state.iq_bytes_received, memory_order_relaxed);
    out->ring_overflow_count = atomic_load_explicit(&g_state.ring_overflow_count, memory_order_relaxed);
    out->rf_level_dbfs = atomic_load_explicit(&g_state.rf_level_dbfs, memory_order_relaxed);
    out->audio_level_dbfs = atomic_load_explicit(&g_state.audio_level_dbfs, memory_order_relaxed);
    out->squelch_open = atomic_load_explicit(&g_state.squelch_open, memory_order_relaxed);
    out->recording_bytes_written = atomic_load_explicit(&g_state.recording_bytes_written, memory_order_relaxed);
    out->stereo_locked = atomic_load_explicit(&g_state.stereo_locked, memory_order_relaxed);
    out->pilot_level = atomic_load_explicit(&g_state.pilot_level, memory_order_relaxed);
    return SHIM_OK;
}

int32_t shim_get_spectrum_db(float *out_mag_db, int32_t num_bins) {
    if (!out_mag_db || num_bins <= 0 || num_bins > SPECTRUM_FFT_SIZE) {
        return SHIM_ERR_INVALID_ARG;
    }
    if (!atomic_load_explicit(&g_state.spectrum_valid, memory_order_relaxed)) {
        return 0;
    }

    pthread_mutex_lock(&g_state.spectrum_lock);
    if (num_bins == SPECTRUM_FFT_SIZE) {
        memcpy(out_mag_db, g_state.spectrum_snapshot, sizeof(float) * (size_t)num_bins);
    } else {
        /* downsample by simple bin-averaging to the requested num_bins */
        for (int32_t i = 0; i < num_bins; i++) {
            int start = (int)((int64_t)i * SPECTRUM_FFT_SIZE / num_bins);
            int end = (int)((int64_t)(i + 1) * SPECTRUM_FFT_SIZE / num_bins);
            if (end <= start) {
                end = start + 1;
            }
            float sum = 0.0f;
            int count = 0;
            for (int k = start; k < end && k < SPECTRUM_FFT_SIZE; k++) {
                sum += g_state.spectrum_snapshot[k];
                count++;
            }
            out_mag_db[i] = (count > 0) ? (sum / (float)count) : -180.0f;
        }
    }
    pthread_mutex_unlock(&g_state.spectrum_lock);
    return num_bins;
}

int32_t shim_start_recording(const char *file_path) {
    if (!file_path) {
        return SHIM_ERR_INVALID_ARG;
    }
    if (!atomic_load(&g_state.is_streaming)) {
        return SHIM_ERR_NOT_STREAMING;
    }

    pthread_mutex_lock(&g_state.record_lock);
    if (atomic_load(&g_state.recording_active)) {
        pthread_mutex_unlock(&g_state.record_lock);
        return SHIM_ERR_RECORDING_ACTIVE;
    }

    /* Current channel count (1 mono NFM/AM, 2 stereo WFM — always 2 in
     * WFM even without pilot lock, see audio_channel_count in
     * dsp_thread_main) at AUDIO_TARGET_HZ, the same format as the pcm_out
     * dsp_thread is already producing. Consistent with the rest of
     * recording because the UI (device_screen.dart) always stops an
     * in-progress recording before switching modes — it never keeps
     * recording with the wrong channel count mid WFM<->NFM/AM switch. */
    int channels = atomic_load_explicit(&g_state.audio_channel_count, memory_order_relaxed);
    if (channels != 1 && channels != 2) {
        channels = 1;
    }
    wav_writer_t *writer = wav_writer_open(file_path, AUDIO_TARGET_HZ, channels);
    if (!writer) {
        pthread_mutex_unlock(&g_state.record_lock);
        LOGE("shim_start_recording: failed to open '%s'", file_path);
        return SHIM_ERR_RECORDING_OPEN_FAILED;
    }

    g_state.record_writer = writer;
    atomic_store(&g_state.recording_bytes_written, 0);
    atomic_store(&g_state.recording_active, 1);
    pthread_mutex_unlock(&g_state.record_lock);
    return SHIM_OK;
}

int32_t shim_stop_recording(void) {
    return stop_recording_if_active() ? SHIM_OK : SHIM_ERR_NOT_RECORDING;
}

int32_t shim_is_recording(void) {
    return atomic_load(&g_state.recording_active) ? 1 : 0;
}
