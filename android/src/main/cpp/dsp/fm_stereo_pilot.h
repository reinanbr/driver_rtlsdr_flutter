#ifndef RTLSDR_FM_STEREO_PILOT_H
#define RTLSDR_FM_STEREO_PILOT_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * PLL de 2ª ordem travado no piloto de 19kHz do multiplex FM estéreo —
 * roda direto sobre o MPX cru (audio_pre, sem de-ênfase, sem bandpass
 * dedicado: o próprio loop estreito do PLL já funciona como filtro de
 * rastreio, técnica padrão usada por decodificadores FM estéreo
 * open-source como o SoftFM — um BPF explícito só adicionaria atraso de
 * grupo pra compensar depois, sem ganho real).
 *
 * Gera os harmônicos de 2ª e 3ª ordem via identidades de ângulo duplo/soma
 * a partir da própria fase do NCO — cos(2θ)/sin(2θ) pro demux L-R em
 * 38kHz (usado já no estéreo), cos(3θ)/sin(3θ) pra downconversão do RDS em
 * 57kHz (usado só a partir do decodificador RDS) — sem precisar de um
 * segundo/terceiro NCO:
 *   sin(2θ) = 2·sinθ·cosθ            cos(2θ) = cos²θ − sin²θ
 *   sin(3θ) = sin(2θ)·cosθ + cos(2θ)·sinθ    cos(3θ) = cos(2θ)·cosθ − sin(2θ)·sinθ
 *
 * AVISO (não validado em hardware real — sem dongle disponível no ambiente
 * de desenvolvimento): os ganhos do loop (banda passante ~8Hz, zeta~0.707)
 * e os limiares de amplitude de lock em PILOT_LOCK_AMPLITUDE/
 * PILOT_UNLOCK_AMPLITUDE (fm_stereo_pilot.c) são estimativas de partida.
 * Esperado precisar de ajuste no dongle real — em especial se o offset de
 * frequência do cristal do dongle (comum em dongles baratos, pode chegar a
 * centenas de Hz) exceder a faixa de captura do loop, o que impediria o
 * lock mesmo com sinal de RF bom.
 */
typedef struct {
    float theta; /* fase do NCO, rad, wrapped a ±pi */
    float freq;  /* frequência do NCO, rad/amostra */
    float alpha; /* ganho proporcional do loop PI */
    float beta;  /* ganho integral do loop PI */

    /* Detector de amplitude do piloto (decisão de lock) — LPF de 1º polo
     * sobre a correlação I/Q com o próprio NCO; não realimenta o loop de
     * fase, só informa locked/last_amplitude. */
    float lock_lpf_i;
    float lock_lpf_q;
    float lock_alpha;
    float last_amplitude;

    int locked;
    int debounce_counter;
} fm_stereo_pilot_t;

void fm_stereo_pilot_init(fm_stereo_pilot_t *p, float sample_rate_hz);

/* Processa `count` amostras do MPX cru (audio_pre, sem de-ênfase). Escreve
 * cos(2θ)/sin(2θ)/cos(3θ)/sin(3θ) em arrays de tamanho `count` fornecidos
 * pelo chamador — qualquer um dos 4 ponteiros pode ser NULL pra pular essa
 * saída (ex.: o demux estéreo só precisa de cos2wt; sin2wt/cos3wt/sin3wt
 * ficam NULL até o decodificador RDS chegar). */
void fm_stereo_pilot_process(fm_stereo_pilot_t *p, const float *mpx, size_t count, float *cos2wt, float *sin2wt,
                              float *cos3wt, float *sin3wt);

int fm_stereo_pilot_locked(const fm_stereo_pilot_t *p);
float fm_stereo_pilot_amplitude(const fm_stereo_pilot_t *p);

#ifdef __cplusplus
}
#endif

#endif
