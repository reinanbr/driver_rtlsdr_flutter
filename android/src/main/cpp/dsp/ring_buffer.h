#ifndef RTLSDR_RING_BUFFER_H
#define RTLSDR_RING_BUFFER_H

#include <stdatomic.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Lock-free single-producer/single-consumer ring buffer. `capacity` must
 * be a power of 2 (indexing via mask instead of modulo). Uses
 * monotonically increasing head/tail counters (not modulo capacity) —
 * size_t wraparound is safe here because only the *differences* between
 * them matter.
 *
 * Intended use: 1 producer (USB callback) and 1 consumer (DSP/drain
 * thread) per instance. Not safe with multiple simultaneous producers or
 * consumers.
 */
typedef struct {
    uint8_t *buffer;
    size_t capacity;
    _Atomic size_t head;
    _Atomic size_t tail;
} ring_buffer_t;

int ring_buffer_init(ring_buffer_t *rb, size_t capacity_pow2);
void ring_buffer_destroy(ring_buffer_t *rb);
void ring_buffer_reset(ring_buffer_t *rb);

/* Writes up to len bytes; returns how many bytes fit (may be < len if the
 * buffer is full — caller should treat that as overflow). */
size_t ring_buffer_write(ring_buffer_t *rb, const uint8_t *data, size_t len);

/* Reads up to len bytes; returns how many bytes were read (0 if empty). */
size_t ring_buffer_read(ring_buffer_t *rb, uint8_t *out, size_t len);

size_t ring_buffer_available_read(const ring_buffer_t *rb);
size_t ring_buffer_available_write(const ring_buffer_t *rb);

#ifdef __cplusplus
}
#endif

#endif
