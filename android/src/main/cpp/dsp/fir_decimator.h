#ifndef RTLSDR_FIR_DECIMATOR_H
#define RTLSDR_FIR_DECIMATOR_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Decimador FIR passa-baixa (janela de Hamming) genérico — usado tanto para
 * decimar o IQ complexo (anti-aliasing antes de reduzir a taxa de amostras)
 * quanto o áudio real pós-discriminador (in_q/out_q = NULL nesse caso).
 *
 * Implementação "naive": mantém um histórico circular e só computa o
 * produto interno com os taps nos instantes de decimação (a cada N
 * amostras de entrada) — correto e simples, custo O(num_taps) por amostra
 * de SAÍDA (decimada), não por amostra de entrada.
 */
typedef struct {
    float *taps;
    int num_taps;
    float *hist_i;
    float *hist_q; /* NULL se usado só para sinal real */
    int write_pos;
    int filled;
    int decim_factor;
    int phase;
} fir_decimator_t;

/* cutoff_normalized: 0..1, onde 1.0 = Nyquist da taxa de ENTRADA. Use algo
 * como 0.9 / decim_factor pra deixar margem de transição antes do próximo
 * Nyquist (da taxa decimada). complex_mode = 1 para operar com I/Q, 0 para
 * sinal real (in_q/out_q ignorados em fir_decimator_process). */
int fir_decimator_init(fir_decimator_t *d, int decim_factor, int num_taps, float cutoff_normalized, int complex_mode);
void fir_decimator_destroy(fir_decimator_t *d);

/* Processa in_count amostras de entrada; escreve as amostras decimadas em
 * out_i (e out_q, se complex_mode) até out_capacity; retorna quantas
 * amostras decimadas foram escritas. in_q/out_q podem ser NULL em modo
 * real. */
size_t fir_decimator_process(fir_decimator_t *d, const float *in_i, const float *in_q, size_t in_count, float *out_i,
                              float *out_q, size_t out_capacity);

#ifdef __cplusplus
}
#endif

#endif
