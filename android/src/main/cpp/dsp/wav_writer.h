#ifndef RTLSDR_WAV_WRITER_H
#define RTLSDR_WAV_WRITER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Incremental WAV (PCM16) writer — intended for the DSP thread to dump
 * samples as they arrive, without keeping everything in memory. The
 * final size is only known at wav_writer_close(), so the RIFF/data
 * header is written with placeholders in wav_writer_open() and fixed up
 * via fseek on close.
 */
typedef struct wav_writer wav_writer_t;

/* Opens `path` and writes the provisional WAV header (44 bytes, PCM16).
 * `channels` must be 1 (mono) or 2 (interleaved stereo L,R,L,R...).
 * Returns NULL on error (invalid path, no write permission, etc). */
wav_writer_t *wav_writer_open(const char *path, uint32_t sample_rate_hz, int channels);

/* Same as wav_writer_open(), but writes through an already-open file
 * descriptor (e.g. one obtained from Android's MediaStore/ContentResolver
 * for a destination — like the public Downloads folder — with no plain
 * filesystem path available). Takes ownership of `fd`: closing the writer
 * closes it. */
wav_writer_t *wav_writer_open_fd(int fd, uint32_t sample_rate_hz, int channels);

/* Writes `num_frames` frames (1 frame = `channels` interleaved int16
 * samples) — `pcm` must have `num_frames * channels` valid samples.
 * Returns 0 on success, < 0 if the write didn't complete. */
int wav_writer_write(wav_writer_t *w, const int16_t *pcm, size_t num_frames);

/* Fixes up the RIFF/data header size fields with the final total and
 * closes the file. Always frees `w` (even if `w` is NULL or the
 * fseek/fwrite fixup fails) — safe to call exactly once per successful
 * wav_writer_open(). */
void wav_writer_close(wav_writer_t *w);

#ifdef __cplusplus
}
#endif

#endif
