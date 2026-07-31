#ifndef RTLSDR_IQ_WRITER_H
#define RTLSDR_IQ_WRITER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Raw I/Q writer — dumps the interleaved 8-bit unsigned I/Q samples
 * exactly as the RTL2832U delivers them (no header, just I,Q,I,Q... bytes
 * centered at ~127.5 — the same ".cu8" convention rtl_sdr/GNU Radio/gqrx
 * use for raw captures), so a recording from this driver opens directly
 * in those tools for offline analysis. Tapped in dsp_thread_main BEFORE
 * the two-stage decimation/demodulation (rtlsdr_shim.c) — a faithful,
 * demod_mode-independent capture of exactly what the dongle sent, useful
 * for signals this driver doesn't demodulate (yet).
 */
typedef struct iq_writer iq_writer_t;

/* Opens `path` for writing. Returns NULL on error (invalid path, no write
 * permission, etc). */
iq_writer_t *iq_writer_open(const char *path);

/* Same as iq_writer_open(), but writes through an already-open file
 * descriptor (e.g. one obtained from Android's MediaStore/ContentResolver
 * for a destination — like the public Downloads folder — with no plain
 * filesystem path available). Takes ownership of `fd`: closing the writer
 * closes it. */
iq_writer_t *iq_writer_open_fd(int fd);

/* Writes `count` raw bytes (already-interleaved I,Q,I,Q... uint8 pairs —
 * same layout as a ring_buffer_read chunk). Returns 0 on success, < 0 if
 * the write didn't complete. */
int iq_writer_write(iq_writer_t *w, const uint8_t *data, size_t count);

/* Closes the file. Always frees `w` (even if `w` is NULL) — safe to call
 * exactly once per successful iq_writer_open(). */
void iq_writer_close(iq_writer_t *w);

#ifdef __cplusplus
}
#endif

#endif
