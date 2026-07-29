#include "spectrum_fft.h"

#include <math.h>
#include <stdlib.h>

#include "../vendor/kissfft/kiss_fft.h"

#define SPECTRUM_PI 3.14159265358979323846f

int spectrum_fft_init(spectrum_fft_t *s, int fft_size) {
    s->fft_size = fft_size;
    s->cfg = kiss_fft_alloc(fft_size, 0 /* forward */, NULL, NULL);
    s->window = (float *)malloc(sizeof(float) * (size_t)fft_size);
    s->in_buf = malloc(sizeof(kiss_fft_cpx) * (size_t)fft_size);
    s->out_buf = malloc(sizeof(kiss_fft_cpx) * (size_t)fft_size);
    if (!s->cfg || !s->window || !s->in_buf || !s->out_buf) {
        spectrum_fft_destroy(s);
        return -1;
    }

    /* janela de Hann — reduz vazamento espectral (spectral leakage) das
     * bordas do bloco analisado. */
    for (int n = 0; n < fft_size; n++) {
        s->window[n] = 0.5f * (1.0f - cosf(2.0f * SPECTRUM_PI * (float)n / (float)(fft_size - 1)));
    }

    return 0;
}

void spectrum_fft_destroy(spectrum_fft_t *s) {
    free(s->cfg);
    free(s->window);
    free(s->in_buf);
    free(s->out_buf);
    s->cfg = NULL;
    s->window = NULL;
    s->in_buf = NULL;
    s->out_buf = NULL;
}

void spectrum_fft_process(spectrum_fft_t *s, const float *in_i, const float *in_q, float *out_db) {
    int n = s->fft_size;
    kiss_fft_cpx *in = (kiss_fft_cpx *)s->in_buf;
    kiss_fft_cpx *out = (kiss_fft_cpx *)s->out_buf;

    for (int k = 0; k < n; k++) {
        in[k].r = in_i[k] * s->window[k];
        in[k].i = in_q[k] * s->window[k];
    }

    kiss_fft((kiss_fft_cfg)s->cfg, in, out);

    /* fftshift: bin 0 da FFT crua é DC; queremos DC no meio (metade
     * negativa da banda antes, metade positiva depois — ordem natural de
     * exibição de espectro). */
    int half = n / 2;
    for (int k = 0; k < n; k++) {
        int src = (k + half) % n;
        float re = out[src].r;
        float im = out[src].i;
        float mag = sqrtf(re * re + im * im) / (float)n;
        out_db[k] = (mag > 1e-9f) ? 20.0f * log10f(mag) : -180.0f;
    }
}
