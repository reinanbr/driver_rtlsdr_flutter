#ifndef RTLSDR_DEMOD_AM_H
#define RTLSDR_DEMOD_AM_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Detecção de envelope (AM) + bloqueio de DC — o envelope de um sinal AM
 * carrega um offset DC grande (proporcional à portadora) que precisa ser
 * removido antes de virar áudio. */
typedef struct {
    float dc_prev_in;
    float dc_prev_out;
} am_demod_t;

void am_demod_init(am_demod_t *d);

void am_demod_process(am_demod_t *d, const float *in_i, const float *in_q, size_t count, float *out_audio);

#ifdef __cplusplus
}
#endif

#endif
