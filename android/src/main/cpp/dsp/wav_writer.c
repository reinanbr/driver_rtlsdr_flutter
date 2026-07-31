#include "wav_writer.h"

#include <stdio.h>
#include <stdlib.h>

struct wav_writer {
    FILE *fp;
    int channels;
    uint64_t data_bytes_written;
};

/* Canonical 44-byte WAV header (PCM). The two size fields (RIFF chunk
 * size and data chunk size) are written as 0 here and fixed up in
 * wav_writer_close() — streaming, so the final size is only known there. */
static int write_placeholder_header(FILE *fp, uint32_t sample_rate_hz, int channels) {
    uint16_t num_channels = (uint16_t)channels;
    uint16_t bits_per_sample = 16;
    uint32_t byte_rate = sample_rate_hz * (uint32_t)num_channels * (bits_per_sample / 8);
    uint16_t block_align = (uint16_t)(num_channels * (bits_per_sample / 8));
    uint32_t zero32 = 0;
    uint16_t audio_format_pcm = 1;
    uint32_t fmt_chunk_size = 16;

    if (fwrite("RIFF", 1, 4, fp) != 4) return -1;
    if (fwrite(&zero32, 4, 1, fp) != 1) return -1; /* RIFF chunk size, placeholder */
    if (fwrite("WAVE", 1, 4, fp) != 4) return -1;

    if (fwrite("fmt ", 1, 4, fp) != 4) return -1;
    if (fwrite(&fmt_chunk_size, 4, 1, fp) != 1) return -1;
    if (fwrite(&audio_format_pcm, 2, 1, fp) != 1) return -1;
    if (fwrite(&num_channels, 2, 1, fp) != 1) return -1;
    if (fwrite(&sample_rate_hz, 4, 1, fp) != 1) return -1;
    if (fwrite(&byte_rate, 4, 1, fp) != 1) return -1;
    if (fwrite(&block_align, 2, 1, fp) != 1) return -1;
    if (fwrite(&bits_per_sample, 2, 1, fp) != 1) return -1;

    if (fwrite("data", 1, 4, fp) != 4) return -1;
    if (fwrite(&zero32, 4, 1, fp) != 1) return -1; /* data chunk size, placeholder */

    return 0;
}

static wav_writer_t *wav_writer_open_fp(FILE *fp, uint32_t sample_rate_hz, int channels) {
    if (write_placeholder_header(fp, sample_rate_hz, channels) != 0) {
        fclose(fp);
        return NULL;
    }

    wav_writer_t *w = (wav_writer_t *)malloc(sizeof(wav_writer_t));
    if (!w) {
        fclose(fp);
        return NULL;
    }
    w->fp = fp;
    w->channels = channels;
    w->data_bytes_written = 0;
    return w;
}

wav_writer_t *wav_writer_open(const char *path, uint32_t sample_rate_hz, int channels) {
    if (!path || (channels != 1 && channels != 2)) {
        return NULL;
    }

    FILE *fp = fopen(path, "wb");
    if (!fp) {
        return NULL;
    }
    return wav_writer_open_fp(fp, sample_rate_hz, channels);
}

wav_writer_t *wav_writer_open_fd(int fd, uint32_t sample_rate_hz, int channels) {
    if (fd < 0 || (channels != 1 && channels != 2)) {
        return NULL;
    }

    FILE *fp = fdopen(fd, "wb");
    if (!fp) {
        return NULL;
    }
    return wav_writer_open_fp(fp, sample_rate_hz, channels);
}

int wav_writer_write(wav_writer_t *w, const int16_t *pcm, size_t num_frames) {
    if (!w || !w->fp || !pcm) {
        return -1;
    }
    size_t samples = num_frames * (size_t)w->channels;
    size_t written = fwrite(pcm, sizeof(int16_t), samples, w->fp);
    w->data_bytes_written += written * sizeof(int16_t);
    return (written == samples) ? 0 : -1;
}

void wav_writer_close(wav_writer_t *w) {
    if (!w) {
        return;
    }
    if (w->fp) {
        /* 36 = size of the whole header (44 bytes) minus the 8 bytes of
         * "RIFF"+size that aren't counted in the RIFF size itself. */
        uint32_t data_size = (uint32_t)w->data_bytes_written;
        uint32_t riff_size = 36u + data_size;

        if (fseek(w->fp, 4, SEEK_SET) == 0) {
            fwrite(&riff_size, 4, 1, w->fp);
        }
        if (fseek(w->fp, 40, SEEK_SET) == 0) {
            fwrite(&data_size, 4, 1, w->fp);
        }
        fclose(w->fp);
    }
    free(w);
}
