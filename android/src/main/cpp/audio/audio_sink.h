#ifndef RTLSDR_AUDIO_SINK_H
#define RTLSDR_AUDIO_SINK_H

#include <stddef.h>
#include <stdint.h>

/*
 * Fronteira C simples entre a thread de DSP (C, rtlsdr_shim.c) e o Oboe
 * (C++, audio_sink_oboe.cpp) — evita incluir dsp/ring_buffer.h (que usa
 * `_Atomic`, sintaxe C11 não totalmente padrão em C++17) direto num
 * arquivo .cpp; o pull_cb decide como buscar os frames de PCM.
 */

#ifdef __cplusplus
extern "C" {
#endif

/* Chamado pela thread de áudio do Oboe (alta prioridade — nunca deve
 * bloquear). `num_frames` é sempre uma contagem de FRAMES (1 frame = N
 * amostras int16 intercaladas, N = channel_count passado a
 * audio_sink_start — 1 em mono, 2 em estéreo L,R,L,R...), não de amostras
 * brutas. Deve retornar quantos frames preencheu de fato em `out`
 * (`out` precisa ter espaço pra num_frames*channel_count amostras); se
 * menos que num_frames, o restante vira silêncio. */
typedef size_t (*audio_pull_cb_t)(int16_t *out, size_t num_frames, void *user_data);

/* Abre e inicia o stream de saída do Oboe na taxa pedida (int16,
 * channel_count 1 = mono ou 2 = estéreo). Retorna 0 em sucesso. */
int audio_sink_start(uint32_t sample_rate_hz, int channel_count, audio_pull_cb_t pull_cb, void *user_data);

/* Para e fecha o stream. Idempotente (seguro chamar mesmo se não estiver
 * aberto). */
void audio_sink_stop(void);

#ifdef __cplusplus
}
#endif

#endif
