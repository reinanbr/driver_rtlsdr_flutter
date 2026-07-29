#ifndef RTLSDR_DEEMPHASIS_H
#define RTLSDR_DEEMPHASIS_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * De-ênfase de um polo — mesma matemática que antes vinha embutida em
 * demod_fm.c, agora extraída como módulo independente porque o estéreo WFM
 * precisa aplicá-la duas vezes (uma por canal L/R), DEPOIS do split
 * piloto/L-R e da decimação de áudio — não mais uma vez sobre o MPX inteiro
 * antes do split (o MPX cru precisa sobreviver intacto até depois do demux
 * de 38kHz; ver rtlsdr_shim.c, onde fm_demod_init roda com
 * deemphasis_tau_us=0 para WFM agora — o discriminador só entrega o MPX
 * cru, sem filtrar nada).
 */
typedef struct {
    float state;
    float alpha;
} deemphasis_t;

/* sample_rate_hz: taxa na qual o filtro roda (pós-decimação de áudio — bem
 * mais baixa que a taxa de MPX onde a de-ênfase rodava antes, mas
 * matematicamente equivalente: é um filtro shelf de baixa frequência, bem
 * abaixo do corte da decimação). tau_us: 50 ou 75 (Europa/mundo vs
 * EUA/Coreia). */
void deemphasis_init(deemphasis_t *d, float sample_rate_hz, float tau_us);

void deemphasis_process(deemphasis_t *d, const float *in, size_t count, float *out);

#ifdef __cplusplus
}
#endif

#endif
