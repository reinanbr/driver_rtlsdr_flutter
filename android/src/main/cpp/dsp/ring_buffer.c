#include "ring_buffer.h"

#include <stdlib.h>

int ring_buffer_init(ring_buffer_t *rb, size_t capacity_pow2) {
    if (capacity_pow2 == 0 || (capacity_pow2 & (capacity_pow2 - 1)) != 0) {
        return -1; /* precisa ser potência de 2 para a máscara de índice funcionar */
    }
    rb->buffer = (uint8_t *)malloc(capacity_pow2);
    if (!rb->buffer) {
        return -1;
    }
    rb->capacity = capacity_pow2;
    atomic_init(&rb->head, 0);
    atomic_init(&rb->tail, 0);
    return 0;
}

void ring_buffer_destroy(ring_buffer_t *rb) {
    free(rb->buffer);
    rb->buffer = NULL;
    rb->capacity = 0;
}

void ring_buffer_reset(ring_buffer_t *rb) {
    atomic_store(&rb->head, 0);
    atomic_store(&rb->tail, 0);
}

size_t ring_buffer_available_read(const ring_buffer_t *rb) {
    size_t head = atomic_load_explicit((_Atomic size_t *)&rb->head, memory_order_acquire);
    size_t tail = atomic_load_explicit((_Atomic size_t *)&rb->tail, memory_order_relaxed);
    return head - tail;
}

size_t ring_buffer_available_write(const ring_buffer_t *rb) {
    return rb->capacity - ring_buffer_available_read(rb);
}

size_t ring_buffer_write(ring_buffer_t *rb, const uint8_t *data, size_t len) {
    size_t head = atomic_load_explicit(&rb->head, memory_order_relaxed);
    size_t tail = atomic_load_explicit(&rb->tail, memory_order_acquire);
    size_t free_space = rb->capacity - (head - tail);

    if (len > free_space) {
        len = free_space;
    }

    size_t mask = rb->capacity - 1;
    for (size_t i = 0; i < len; i++) {
        rb->buffer[(head + i) & mask] = data[i];
    }

    atomic_store_explicit(&rb->head, head + len, memory_order_release);
    return len;
}

size_t ring_buffer_read(ring_buffer_t *rb, uint8_t *out, size_t len) {
    size_t tail = atomic_load_explicit(&rb->tail, memory_order_relaxed);
    size_t head = atomic_load_explicit(&rb->head, memory_order_acquire);
    size_t available = head - tail;

    if (len > available) {
        len = available;
    }

    size_t mask = rb->capacity - 1;
    for (size_t i = 0; i < len; i++) {
        out[i] = rb->buffer[(tail + i) & mask];
    }

    atomic_store_explicit(&rb->tail, tail + len, memory_order_release);
    return len;
}
