#ifndef RTLSDR_SPECTRUM_FFT_H
#define RTLSDR_SPECTRUM_FFT_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * FFT complexa (KissFFT) sobre uma janela de amostras IQ brutas (pré-
 * decimação), pra dar uma visão da banda inteira capturada — não é o canal
 * estreito que o demodulador usa. Usado pro waterfall/espectro (M5).
 */
typedef struct {
    void *cfg; /* kiss_fft_cfg */
    int fft_size;
    float *window;   /* coeficientes da janela de Hann, tamanho fft_size */
    void *in_buf;  /* kiss_fft_cpx*, alocado uma vez em spectrum_fft_init */
    void *out_buf; /* kiss_fft_cpx*, idem */
} spectrum_fft_t;

int spectrum_fft_init(spectrum_fft_t *s, int fft_size);
void spectrum_fft_destroy(spectrum_fft_t *s);

/* in_i/in_q: exatamente fft_size amostras IQ (mais recentes). out_db:
 * fft_size valores de magnitude em dB, já reordenados (fftshift) — out_db[0]
 * é a borda inferior da banda capturada (frequência central - metade da
 * taxa de amostragem) e out_db[fft_size-1] é a borda superior, DC no meio
 * — ordem pronta pra desenhar direto num espectro/waterfall. */
void spectrum_fft_process(spectrum_fft_t *s, const float *in_i, const float *in_q, float *out_db);

#ifdef __cplusplus
}
#endif

#endif
