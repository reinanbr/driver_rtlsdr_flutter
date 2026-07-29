#ifndef RTLSDR_RDS_DECODER_H
#define RTLSDR_RDS_DECODER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Decodificador RDS (RBDS): downconversão coerente do subportador de
 * 57kHz (3ª harmônica do piloto de 19kHz, reaproveitando a mesma PLL do
 * estéreo — ver dsp/fm_stereo_pilot.h) + decimação, recuperação de clock
 * de símbolo (Gardner) na taxa de chip biphase (2375Hz = 2x a taxa de bit
 * de 1187.5Hz), loop de Costas BPSK pra corrigir rotação de fase residual,
 * combinação de par biphase + decodificação diferencial -> bitstream,
 * sincronismo de bloco de 26 bits (CRC/offset words A/B/C/C'/D) e parsing
 * de grupo (PI, PTY, TP, TA, PS via grupo 0A, RadioText via grupo 2A/2B).
 *
 * Constantes verificadas contra uma implementação de referência de código
 * aberto ativamente mantida (redsea, github.com/windytan/redsea — MIT):
 * o polinômio gerador do CRC, os 5 valores de offset word/síndrome e a
 * matriz de verificação de paridade de 26 linhas foram conferidos byte a
 * byte contra o código-fonte de lá (não confiados de memória) — ver
 * RDS_PARITY_CHECK_MATRIX/rds_offset_for_syndrome em rds_decoder.c. O
 * restante (front-end de DSP: downconversão, Gardner, Costas, combinação
 * biphase) é uma implementação própria, mais simples que a de referências
 * como redsea (que usa liquid-dsp e reamostragem fracionária mais
 * sofisticada) — ver AVISO abaixo.
 *
 * AVISO (não validado em hardware real — sem dongle disponível no ambiente
 * de desenvolvimento): esta é a peça de maior risco de todo o projeto.
 * Simplificações assumidas, cada uma um ponto de falha em potencial:
 *   - Gardner com interpolação linear de 2 pontos e uma aproximação pro
 *     "mid sample" (ponto médio entre os dois últimos chips decididos, em
 *     vez de uma interpolação independente a -sps/2) — válida perto do
 *     lock, mas menos precisa que uma implementação de referência.
 *   - Aquisição de sincronismo de bloco ancorada só no offset A (exige a
 *     sequência A->B confirmada a +26 bits) em vez de buscar os 5 offsets
 *     em paralelo — mais simples, um pouco mais lenta pra travar.
 *   - Ambiguidade de qual chip do par biphase vem "primeiro": corrigida
 *     por um fallback (alterna a paridade assumida se ficar muito tempo
 *     sem travar sincronismo de bloco), não resolvida analiticamente.
 *   - Sem correção de erro por burst (capacidade de correção do CRC) —
 *     grupos com erro são só descartados.
 *   - Conjunto de caracteres RDS (G0/G1/G2) não mapeado — PS/RadioText são
 *     armazenados como bytes crus, corretos pra estações que só usam
 *     ASCII básico (a maioria), não pros caracteres especiais da tabela
 *     RDS completa.
 * Ganhos de loop (Gardner, Costas) e o corte do filtro de 57kHz são
 * estimativas de partida, mesma categoria de aviso que dsp/fm_stereo_pilot.h.
 */

typedef struct rds_decoder rds_decoder_t;

rds_decoder_t *rds_decoder_create(float mpx_sample_rate_hz);
void rds_decoder_destroy(rds_decoder_t *d);

/* Processa `count` amostras do MPX cru (audio_pre, mesmo buffer que
 * alimenta fm_stereo_pilot_process) junto com as referências de 3ª
 * harmônica cos3wt/sin3wt (mesma PLL, mesmo tamanho `count` — ver
 * fm_stereo_pilot_process). Só deve ser chamado quando o piloto estéreo
 * está travado (RDS é coerente com o piloto por definição do padrão; sem
 * lock não há referência de fase válida pra demodular o RDS). */
void rds_decoder_process(rds_decoder_t *d, const float *mpx, const float *cos3wt, const float *sin3wt, size_t count);

typedef struct {
    uint16_t pi_code;
    uint8_t pty;
    int32_t tp;
    int32_t ta;
    char ps[9];         /* 8 chars + NUL */
    char radiotext[65]; /* 64 chars + NUL */
    uint32_t generation; /* incrementa sempre que ps/radiotext mudam de fato */
    uint32_t valid_group_count;
    int32_t sync_locked;
} rds_snapshot_t;

/* Cópia thread-safe do estado decodificado atual (chamador não precisa
 * lidar com locks internos do decodificador — a sincronização com o
 * shim_rds_info_t exposto ao Dart é feita em rtlsdr_shim.c, mas esta
 * função em si é segura pra chamar da mesma thread que roda
 * rds_decoder_process, que é o único uso previsto). */
void rds_decoder_snapshot(const rds_decoder_t *d, rds_snapshot_t *out);

#ifdef __cplusplus
}
#endif

#endif
