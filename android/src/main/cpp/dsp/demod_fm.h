#ifndef RTLSDR_DEMOD_FM_H
#define RTLSDR_DEMOD_FM_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Discriminador de quadratura genérico, compartilhado entre WFM (rádio
 * comercial banda larga) e NFM (banda estreita, rádio amador/PMR) — a
 * matemática do discriminador é idêntica nos dois casos; só o desvio
 * máximo esperado e a de-ênfase mudam. Mono apenas — sem estéreo/RDS.
 */
typedef struct {
    float prev_i;
    float prev_q;
    float deemph_state;
    float deemph_alpha;
    float gain;
    int deemphasis_enabled;
} fm_demod_t;

/* sample_rate_hz: taxa complexa de ENTRADA do discriminador (pós-decimação
 * de IQ). max_deviation_hz: desvio máximo esperado (75000 pra WFM, ~5000
 * pra NFM) — define o ganho de escala pra +-1.0 de amplitude de áudio.
 * deemphasis_tau_us: 50 ou 75 pra WFM; use <= 0 pra desativar (NFM não usa
 * pré-ênfase de broadcast). */
void fm_demod_init(fm_demod_t *d, float sample_rate_hz, float max_deviation_hz, float deemphasis_tau_us);

void fm_demod_process(fm_demod_t *d, const float *in_i, const float *in_q, size_t count, float *out_audio);

#ifdef __cplusplus
}
#endif

#endif
