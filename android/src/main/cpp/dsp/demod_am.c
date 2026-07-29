#include "demod_am.h"

#include <math.h>

/* Coeficiente do bloqueador de DC (passa-alta de um polo): quanto mais
 * perto de 1.0, mais baixa a frequência de corte. 0.995 corta bem abaixo
 * de 100 Hz nas taxas de áudio usadas aqui (~32 kHz). */
#define AM_DC_BLOCK_COEFF 0.995f

void am_demod_init(am_demod_t *d) {
    d->dc_prev_in = 0.0f;
    d->dc_prev_out = 0.0f;
}

void am_demod_process(am_demod_t *d, const float *in_i, const float *in_q, size_t count, float *out_audio) {
    float dc_prev_in = d->dc_prev_in;
    float dc_prev_out = d->dc_prev_out;

    for (size_t n = 0; n < count; n++) {
        float i = in_i[n];
        float q = in_q[n];

        /* detector de envelope: magnitude do baseband complexo */
        float envelope = sqrtf(i * i + q * q);

        /* bloqueador de DC: remove o offset grande que a portadora deixa */
        float dc_out = envelope - dc_prev_in + AM_DC_BLOCK_COEFF * dc_prev_out;
        dc_prev_in = envelope;
        dc_prev_out = dc_out;

        out_audio[n] = dc_out;
    }

    d->dc_prev_in = dc_prev_in;
    d->dc_prev_out = dc_prev_out;
}
