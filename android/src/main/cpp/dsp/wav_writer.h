#ifndef RTLSDR_WAV_WRITER_H
#define RTLSDR_WAV_WRITER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Escritor de WAV (PCM16) incremental — pensado pra thread de DSP despejar
 * amostras conforme chegam, sem guardar tudo em memória. O tamanho final só
 * é conhecido em wav_writer_close(), então o header RIFF/data é escrito com
 * placeholders em wav_writer_open() e corrigido por fseek no close.
 */
typedef struct wav_writer wav_writer_t;

/* Abre `path` e escreve o header WAV provisório (44 bytes, PCM16).
 * `channels` deve ser 1 (mono) ou 2 (estéreo intercalado L,R,L,R...).
 * Retorna NULL em erro (path inválido, sem permissão de escrita, etc). */
wav_writer_t *wav_writer_open(const char *path, uint32_t sample_rate_hz, int channels);

/* Escreve `num_frames` frames (1 frame = `channels` amostras int16
 * intercaladas) — `pcm` deve ter `num_frames * channels` amostras válidas.
 * Retorna 0 em sucesso, < 0 se a escrita não completou. */
int wav_writer_write(wav_writer_t *w, const int16_t *pcm, size_t num_frames);

/* Corrige os campos de tamanho do header RIFF/data com o total final e
 * fecha o arquivo. Sempre libera `w` (mesmo se `w` for NULL ou se o fseek/
 * fwrite de correção falhar) — seguro chamar exatamente uma vez por
 * wav_writer_open() bem-sucedido. */
void wav_writer_close(wav_writer_t *w);

#ifdef __cplusplus
}
#endif

#endif
