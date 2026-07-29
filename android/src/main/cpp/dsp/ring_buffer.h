#ifndef RTLSDR_RING_BUFFER_H
#define RTLSDR_RING_BUFFER_H

#include <stdatomic.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Ring buffer lock-free single-produtor/single-consumidor. `capacity` deve
 * ser potência de 2 (indexação via máscara em vez de módulo). Usa contadores
 * head/tail monotonicamente crescentes (não módulo capacity) — o wraparound
 * de size_t é seguro aqui porque só as *diferenças* entre eles importam.
 *
 * Uso pretendido: 1 produtor (callback USB) e 1 consumidor (thread de
 * DSP/drain) por instância. Não é seguro com múltiplos produtores ou
 * múltiplos consumidores simultâneos.
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

/* Escreve até len bytes; retorna quantos bytes couberam (pode ser < len se
 * o buffer estiver cheio — chamador deve tratar isso como overflow). */
size_t ring_buffer_write(ring_buffer_t *rb, const uint8_t *data, size_t len);

/* Lê até len bytes; retorna quantos bytes foram lidos (0 se vazio). */
size_t ring_buffer_read(ring_buffer_t *rb, uint8_t *out, size_t len);

size_t ring_buffer_available_read(const ring_buffer_t *rb);
size_t ring_buffer_available_write(const ring_buffer_t *rb);

#ifdef __cplusplus
}
#endif

#endif
