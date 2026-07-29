#ifndef RTLSDR_AUDIO_SINK_H
#define RTLSDR_AUDIO_SINK_H

#include <stddef.h>
#include <stdint.h>

/*
 * Simple C boundary between the DSP thread (C, rtlsdr_shim.c) and Oboe
 * (C++, audio_sink_oboe.cpp) — avoids including dsp/ring_buffer.h (which
 * uses `_Atomic`, C11 syntax not fully standard in C++17) directly in a
 * .cpp file; pull_cb decides how to fetch the PCM frames.
 */

#ifdef __cplusplus
extern "C" {
#endif

/* Called by Oboe's audio thread (high priority — must never block).
 * `num_frames` is always a count of FRAMES (1 frame = N interleaved int16
 * samples, N = channel_count passed to audio_sink_start — 1 for mono, 2
 * for stereo L,R,L,R...), not raw samples. Must return how many frames it
 * actually filled in `out` (`out` needs room for num_frames*channel_count
 * samples); if less than num_frames, the rest becomes silence. */
typedef size_t (*audio_pull_cb_t)(int16_t *out, size_t num_frames, void *user_data);

/* Opens and starts Oboe's output stream at the requested rate (int16,
 * channel_count 1 = mono or 2 = stereo). Returns 0 on success. */
int audio_sink_start(uint32_t sample_rate_hz, int channel_count, audio_pull_cb_t pull_cb, void *user_data);

/* Stops and closes the stream. Idempotent (safe to call even if not
 * open). */
void audio_sink_stop(void);

#ifdef __cplusplus
}
#endif

#endif
