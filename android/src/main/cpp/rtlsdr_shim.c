#include "rtlsdr_shim.h"

#include <android/log.h>
#include <errno.h>
#include <libusb.h>
#include <math.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "audio/audio_sink.h"
#include "dsp/deemphasis.h"
#include "dsp/demod_am.h"
#include "dsp/demod_fm.h"
#include "dsp/fir_decimator.h"
#include "dsp/fm_stereo_pilot.h"
#include "dsp/rds_decoder.h"
#include "dsp/ring_buffer.h"
#include "dsp/spectrum_fft.h"
#include "dsp/wav_writer.h"
#include "rtl-sdr.h"
#include "rtlsdr_open_fd.h"

#define LOG_TAG "rtlsdr_shim"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

/* 4 MiB ~= 1s de margem a 2.048 Msps (2 bytes/amostra) antes de a thread de
 * DSP precisar acompanhar o ritmo. Precisa ser potência de 2 (ver
 * ring_buffer.h). */
#define IQ_RING_CAPACITY (4u * 1024u * 1024u)
/* 256 KiB ~= 2s de margem de PCM estéreo 16-bit a 32kHz (dobrado do valor
 * original de 128 KiB, mono-only, pra cobrir o pior caso WFM estéreo —
 * folga extra em NFM/AM mono é inofensiva). Folga contra jitter de
 * agendamento entre a thread de DSP e o callback de áudio do Oboe. */
#define PCM_RING_CAPACITY (256u * 1024u)
#define DEFAULT_SAMPLE_RATE_HZ 1024000u
#define DEFAULT_FREQUENCY_HZ 100000000u /* 100.0 MHz, dentro da faixa de FM comercial */
#define DEFAULT_SQUELCH_THRESHOLD_DB (-40.0f)

/* Pipeline de DSP: decimação em 2 estágios, parametrizada por modo —
 * IQ bruto -> banda de canal (decimação por inteiro a partir da taxa de
 * captura) -> demodulador -> áudio final (decimação de novo, agora do
 * sinal real pós-demodulação). WFM precisa de banda de canal larga
 * (~200kHz, desvio de até 75kHz); NFM/AM são bem mais estreitos (~10-25kHz)
 * então decimam mais logo no primeiro estágio — menos ruído de banda
 * adjacente entrando no demodulador. */
#define IQ_STAGE_TARGET_WFM_HZ 256000u
#define IQ_STAGE_TARGET_NARROW_HZ 32000u /* NFM e AM */
#define AUDIO_TARGET_HZ 32000u
#define FIR_NUM_TAPS 63
#define DSP_READ_CHUNK_BYTES 4096u
#define WORK_CAPACITY (DSP_READ_CHUNK_BYTES / 2u)

#define WFM_MAX_DEVIATION_HZ 75000.0f
#define WFM_DEEMPHASIS_TAU_US 50.0f /* Europa/maior parte do mundo; EUA/Coreia usam 75 */
#define NFM_MAX_DEVIATION_HZ 5000.0f
#define SQUELCH_HYSTERESIS_DB 2.0f

/* Constante de tempo do blend mono<->estéreo (rampa suave ao ganhar/perder
 * lock do piloto, evita corte abrupto — ver dsp_thread_main). Estimativa de
 * partida (~150ms), não validada em hardware real. */
#define STEREO_BLEND_TAU_S 0.15f

/* Espectro: FFT sobre IQ bruto (banda inteira, pré-decimação), throttled
 * pra ~20Hz (a thread de DSP roda a ~500 iterações/s com o chunk de leitura
 * atual). 1024 bins é bastante granularidade pra um waterfall em tela de
 * celular; shim_get_spectrum_db faz downsample se o chamador pedir menos. */
#define SPECTRUM_FFT_SIZE 1024
#define SPECTRUM_UPDATE_INTERVAL_ITERS 25

typedef struct {
    pthread_mutex_t lock;

    _Atomic int is_open;
    _Atomic int is_streaming;
    _Atomic int stop_requested;

    libusb_context *usb_ctx;
    libusb_device_handle *usb_devh;
    rtlsdr_dev_t *rtl_dev;

    uint32_t frequency_hz;
    uint32_t sample_rate_hz;

    _Atomic int demod_mode; /* demod_mode_t */
    _Atomic float squelch_threshold_db;

    pthread_t usb_thread;
    pthread_t dsp_thread;

    ring_buffer_t iq_ring;
    ring_buffer_t pcm_ring;

    _Atomic uint64_t iq_bytes_received;
    _Atomic uint32_t ring_overflow_count;
    _Atomic float audio_level_dbfs;
    _Atomic float rf_level_dbfs;
    _Atomic int squelch_open;

    /* Estéreo (WFM): stereo_enabled é o toggle do usuário (lido ao vivo,
     * sem precisar reiniciar o streaming — diferente de demod_mode), os
     * outros dois são só-leitura pro Dart, escritos pela dsp_thread a cada
     * bloco. audio_channel_count é lido por pcm_pull_callback (thread do
     * Oboe) pra saber quantas amostras por frame puxar do pcm_ring — 1 ou
     * 2, decidido pela dsp_thread ao iniciar (2 sempre que mode==WFM,
     * mesmo sem lock/com stereo_enabled=0, pra não precisar reabrir o Oboe
     * a cada toggle; ver rtlsdr_shim.h). */
    _Atomic int stereo_enabled;
    _Atomic int stereo_locked;
    _Atomic float pilot_level;
    _Atomic int audio_channel_count;

    /* RDS (WFM) — snapshot protegido por rds_lock, mesmo padrão do
     * espectro (spectrum_lock/spectrum_snapshot): PI/PS/RadioText são
     * variável-tamanho, não cabem num _Atomic simples. rds_enabled é o
     * toggle do usuário, aplicado ao vivo. */
    _Atomic int rds_enabled;
    pthread_mutex_t rds_lock;
    rds_snapshot_t rds_snapshot;

    pthread_mutex_t spectrum_lock;
    float spectrum_snapshot[SPECTRUM_FFT_SIZE];
    _Atomic int spectrum_valid;

    /* Gravação: protegida por record_lock (não pelos atomics sozinhos) —
     * shim_stop_recording pode rodar concorrentemente com a escrita da
     * dsp_thread, e sem lock teria uma janela de use-after-free entre o
     * "recording_active ainda é 1" e o wav_writer_write de fato (ver
     * stop_recording_if_active()). */
    pthread_mutex_t record_lock;
    wav_writer_t *record_writer;
    _Atomic int recording_active;
    _Atomic uint64_t recording_bytes_written;
} shim_state_t;

static shim_state_t g_state = {
    .lock = PTHREAD_MUTEX_INITIALIZER,
    .spectrum_lock = PTHREAD_MUTEX_INITIALIZER,
    .record_lock = PTHREAD_MUTEX_INITIALIZER,
    .rds_lock = PTHREAD_MUTEX_INITIALIZER,
};

/* ---- Callback do leitor USB (chamado de dentro de libusb_handle_events,
 * na usb_thread) — precisa ser rápido: só copia para o ring e conta bytes,
 * sem processar nada aqui. */
static void iq_callback(unsigned char *buf, uint32_t len, void *ctx) {
    (void)ctx;
    if (atomic_load_explicit(&g_state.stop_requested, memory_order_relaxed)) {
        return;
    }

    atomic_fetch_add_explicit(&g_state.iq_bytes_received, len, memory_order_relaxed);

    size_t written = ring_buffer_write(&g_state.iq_ring, buf, len);
    if (written < len) {
        atomic_fetch_add_explicit(&g_state.ring_overflow_count, 1, memory_order_relaxed);
    }
}

static void *usb_thread_main(void *arg) {
    (void)arg;
    rtlsdr_dev_t *rtl_dev = g_state.rtl_dev;

    rtlsdr_reset_buffer(rtl_dev);

    /* Bloqueia até rtlsdr_cancel_async() ser chamado (de outra thread —
     * mesmo padrão usado por rtl_tcp.c upstream: read_async roda numa
     * thread enquanto um comando de outra thread cancela). */
    int r = rtlsdr_read_async(rtl_dev, iq_callback, NULL, 0, 0);
    if (r != 0) {
        LOGE("rtlsdr_read_async saiu com erro %d", r);
    }
    return NULL;
}

/* Chamado pela thread de áudio do Oboe (audio_sink_oboe.cpp) — só puxa do
 * ring de PCM, nunca bloqueia. `num_frames`/retorno são em FRAMES (ver
 * audio_sink.h) — multiplica/divide por audio_channel_count pra converter
 * de/pra amostras int16 intercaladas de fato armazenadas no ring. */
static size_t pcm_pull_callback(int16_t *out, size_t num_frames, void *user_data) {
    (void)user_data;
    int channels = atomic_load_explicit(&g_state.audio_channel_count, memory_order_relaxed);
    if (channels < 1) {
        channels = 1;
    }
    size_t bytes_wanted = num_frames * (size_t)channels * sizeof(int16_t);
    size_t bytes_read = ring_buffer_read(&g_state.pcm_ring, (uint8_t *)out, bytes_wanted);
    return bytes_read / ((size_t)channels * sizeof(int16_t));
}

static inline float clamp_unit(float x) {
    if (x > 1.0f) return 1.0f;
    if (x < -1.0f) return -1.0f;
    return x;
}

static float compute_rms_dbfs(const float *i, const float *q, size_t count) {
    if (count == 0) {
        return -120.0f;
    }
    float sum_sq = 0.0f;
    for (size_t n = 0; n < count; n++) {
        sum_sq += i[n] * i[n] + q[n] * q[n];
    }
    float rms = sqrtf(sum_sq / (float)count);
    return (rms > 1e-9f) ? 20.0f * log10f(rms) : -120.0f;
}

/* Thread de DSP: consome IQ bruto do ring, decimação + demodulador (WFM/
 * NFM/AM, conforme o modo lido no início — trocar de modo exige parar e
 * reiniciar o streaming) + squelch (NFM/AM) + decimação de áudio, escreve
 * PCM no ring de áudio consumido pelo callback do Oboe. */
static void *dsp_thread_main(void *arg) {
    (void)arg;

    uint32_t input_rate = g_state.sample_rate_hz;
    demod_mode_t mode = (demod_mode_t)atomic_load_explicit(&g_state.demod_mode, memory_order_relaxed);
    int squelch_enabled = (mode != DEMOD_WFM);

    uint32_t iq_stage_target_hz = (mode == DEMOD_WFM) ? IQ_STAGE_TARGET_WFM_HZ : IQ_STAGE_TARGET_NARROW_HZ;

    int iq_decim = (int)(input_rate / iq_stage_target_hz);
    if (iq_decim < 1) {
        iq_decim = 1;
    }
    uint32_t iq_stage_rate = input_rate / (uint32_t)iq_decim;

    int audio_decim = (int)(iq_stage_rate / AUDIO_TARGET_HZ);
    if (audio_decim < 1) {
        audio_decim = 1;
    }
    uint32_t audio_rate = iq_stage_rate / (uint32_t)audio_decim;

    /* WFM sempre abre o Oboe em estéreo (2 canais), mesmo sem lock de
     * piloto ou com o usuário preferindo mono — nesse caso os dois canais
     * carregam áudio idêntico (blend=0, ver loop principal). Isso evita
     * fechar/reabrir o stream do Oboe a cada shim_set_stereo_enabled ou
     * cada vez que o piloto trava/destrava, que só troca o atomic
     * stereo_enabled/stereo_locked ao vivo. */
    int channel_count = (mode == DEMOD_WFM) ? 2 : 1;
    atomic_store_explicit(&g_state.audio_channel_count, channel_count, memory_order_relaxed);

    fir_decimator_t iq_stage;
    fir_decimator_t audio_stage;
    if (fir_decimator_init(&iq_stage, iq_decim, FIR_NUM_TAPS, 0.9f / (float)iq_decim, /*complex_mode=*/1) != 0) {
        LOGE("fir_decimator_init (IQ) falhou");
        return NULL;
    }
    /* Em WFM, audio_stage decima L e R em lockstep (complex_mode=1 tratado
     * como dois filtros reais em paralelo, não uma rotação IQ de verdade —
     * ver dsp/fir_decimator.h). NFM/AM continuam decimando um único sinal
     * real, exatamente como antes. */
    if (fir_decimator_init(&audio_stage, audio_decim, FIR_NUM_TAPS, 0.9f / (float)audio_decim,
                            /*complex_mode=*/(mode == DEMOD_WFM) ? 1 : 0) != 0) {
        LOGE("fir_decimator_init (audio) falhou");
        fir_decimator_destroy(&iq_stage);
        return NULL;
    }

    fm_demod_t fm_demod;
    am_demod_t am_demod;
    fm_stereo_pilot_t stereo_pilot;
    rds_decoder_t *rds_decoder = NULL;
    deemphasis_t deemph_l;
    deemphasis_t deemph_r;
    float blend = 0.0f;      /* 0 = mono (L=R=L+R), 1 = estéreo pleno — ver loop principal */
    float blend_alpha = 0.0f;
    switch (mode) {
        case DEMOD_NFM:
            fm_demod_init(&fm_demod, (float)iq_stage_rate, NFM_MAX_DEVIATION_HZ, /*deemphasis=*/0.0f);
            break;
        case DEMOD_AM:
            am_demod_init(&am_demod);
            break;
        case DEMOD_WFM:
        default:
            /* De-ênfase DESLIGADA aqui (0.0f) — diferente de antes. O MPX
             * cru precisa sobreviver intacto (piloto de 19kHz, subportadora
             * de 38kHz) até depois do demux L/R; a de-ênfase de verdade
             * roda depois, por canal, via deemph_l/deemph_r (ver abaixo e
             * dsp/deemphasis.h). */
            fm_demod_init(&fm_demod, (float)iq_stage_rate, WFM_MAX_DEVIATION_HZ, /*deemphasis=*/0.0f);
            fm_stereo_pilot_init(&stereo_pilot, (float)iq_stage_rate);
            rds_decoder = rds_decoder_create((float)iq_stage_rate);
            if (!rds_decoder) {
                LOGE("rds_decoder_create falhou — RDS fica sem dados nesta sessão");
            }
            deemphasis_init(&deemph_l, (float)audio_rate, WFM_DEEMPHASIS_TAU_US);
            deemphasis_init(&deemph_r, (float)audio_rate, WFM_DEEMPHASIS_TAU_US);
            {
                float dt = 1.0f / (float)iq_stage_rate;
                blend_alpha = dt / (STEREO_BLEND_TAU_S + dt);
            }
            break;
    }

    /* Reabrir o stream do Oboe logo após fechar o anterior (ex: reinício
     * automático ao trocar de modo em shim_set_demod_mode/RadioController)
     * pode falhar transitoriamente — o áudio HAL às vezes ainda não
     * terminou de liberar os recursos do stream anterior. Sem retry, o
     * streaming seguia rodando normalmente (IQ, RF, squelch) mas sem
     * áudio nenhum, silenciosamente. */
    int audio_ready = 0;
    for (int attempt = 1; attempt <= 3 && !audio_ready; attempt++) {
        if (audio_sink_start(audio_rate, channel_count, pcm_pull_callback, NULL) == 0) {
            audio_ready = 1;
        } else {
            LOGE("audio_sink_start falhou (tentativa %d/3, taxa %u Hz, %d canais)", attempt, audio_rate,
                 channel_count);
            if (attempt < 3) {
                usleep(100000);
            }
        }
    }
    if (!audio_ready) {
        LOGE("audio_sink_start desistiu após 3 tentativas — streaming vai continuar sem áudio");
    }

    LOGI("Pipeline DSP: modo %d, entrada %u Hz -> decim IQ %d -> %u Hz -> decim audio %d -> %u Hz (%d canal(is))",
         (int)mode, input_rate, iq_decim, iq_stage_rate, audio_decim, audio_rate, channel_count);

    spectrum_fft_t spectrum;
    int spectrum_ok = (spectrum_fft_init(&spectrum, SPECTRUM_FFT_SIZE) == 0);
    if (!spectrum_ok) {
        LOGE("spectrum_fft_init falhou — waterfall fica sem dados nesta sessão");
    }
    int spectrum_counter = 0;
    float spectrum_out[SPECTRUM_FFT_SIZE];

    uint8_t raw[DSP_READ_CHUNK_BYTES];
    float iq_i[WORK_CAPACITY];
    float iq_q[WORK_CAPACITY];
    float stage1_i[WORK_CAPACITY];
    float stage1_q[WORK_CAPACITY];
    float audio_pre[WORK_CAPACITY]; /* MPX cru (WFM) ou áudio demodulado (NFM/AM); reaproveitado como L in-place em WFM */
    float audio_out[WORK_CAPACITY]; /* áudio mono decimado, ou L decimado em WFM */
    int16_t pcm_out[2 * WORK_CAPACITY]; /* mono: audio_count amostras; estéreo: audio_count*2 intercaladas L,R,L,R... */

    /* Só usados em WFM — ver switch(mode) acima onde stereo_pilot é
     * inicializado. cos2wt: referência coerente de 38kHz (2ª harmônica do
     * piloto) pro demux L-R. mpx_diff: L-R banda base, reaproveitado como R
     * in-place (mesma técnica de audio_pre virar L). audio_out_r: R pós-
     * decimação (par de audio_out, que vira L pós-decimação em WFM). */
    float cos2wt[WORK_CAPACITY];
    float mpx_diff[WORK_CAPACITY];
    float audio_out_r[WORK_CAPACITY];

    /* Só usados quando rds_decoder != NULL — 3ª harmônica do piloto
     * (57kHz), mesma PLL de cos2wt, pra downconversão do RDS (ver
     * dsp/rds_decoder.h). */
    float cos3wt[WORK_CAPACITY];
    float sin3wt[WORK_CAPACITY];

    int squelch_was_open = 1;

    while (!atomic_load_explicit(&g_state.stop_requested, memory_order_relaxed)) {
        size_t n = ring_buffer_read(&g_state.iq_ring, raw, sizeof(raw));
        if (n == 0) {
            usleep(2000);
            continue;
        }

        size_t pairs = n / 2;
        for (size_t k = 0; k < pairs; k++) {
            /* RTL2832U entrega IQ 8-bit unsigned offset-binary (0..255,
             * centro em ~127.5) — normaliza pra -1..1. */
            iq_i[k] = ((float)raw[2 * k] - 127.5f) / 127.5f;
            iq_q[k] = ((float)raw[2 * k + 1] - 127.5f) / 127.5f;
        }

        if (spectrum_ok && pairs >= (size_t)SPECTRUM_FFT_SIZE) {
            spectrum_counter++;
            if (spectrum_counter >= SPECTRUM_UPDATE_INTERVAL_ITERS) {
                spectrum_counter = 0;
                /* usa as amostras mais recentes do bloco lido */
                size_t offset = pairs - (size_t)SPECTRUM_FFT_SIZE;
                spectrum_fft_process(&spectrum, &iq_i[offset], &iq_q[offset], spectrum_out);
                pthread_mutex_lock(&g_state.spectrum_lock);
                memcpy(g_state.spectrum_snapshot, spectrum_out, sizeof(spectrum_out));
                pthread_mutex_unlock(&g_state.spectrum_lock);
                atomic_store_explicit(&g_state.spectrum_valid, 1, memory_order_relaxed);
            }
        }

        size_t stage1_count = fir_decimator_process(&iq_stage, iq_i, iq_q, pairs, stage1_i, stage1_q, WORK_CAPACITY);
        if (stage1_count == 0) {
            continue;
        }

        float rf_dbfs = compute_rms_dbfs(stage1_i, stage1_q, stage1_count);
        atomic_store_explicit(&g_state.rf_level_dbfs, rf_dbfs, memory_order_relaxed);

        int squelch_open = 1;
        if (squelch_enabled) {
            float threshold = atomic_load_explicit(&g_state.squelch_threshold_db, memory_order_relaxed);
            float effective_threshold = squelch_was_open ? (threshold - SQUELCH_HYSTERESIS_DB)
                                                           : (threshold + SQUELCH_HYSTERESIS_DB);
            squelch_open = (rf_dbfs >= effective_threshold);
            squelch_was_open = squelch_open;
        }
        atomic_store_explicit(&g_state.squelch_open, squelch_open, memory_order_relaxed);

        size_t audio_count;

        if (mode == DEMOD_AM) {
            am_demod_process(&am_demod, stage1_i, stage1_q, stage1_count, audio_pre);
            audio_count =
                fir_decimator_process(&audio_stage, audio_pre, NULL, stage1_count, audio_out, NULL, WORK_CAPACITY);
        } else if (mode == DEMOD_NFM) {
            fm_demod_process(&fm_demod, stage1_i, stage1_q, stage1_count, audio_pre);
            audio_count =
                fir_decimator_process(&audio_stage, audio_pre, NULL, stage1_count, audio_out, NULL, WORK_CAPACITY);
        } else {
            /* DEMOD_WFM: audio_pre recebe o MPX cru (sem de-ênfase, ver
             * fm_demod_init acima) — piloto de 19kHz + L+R (0-15kHz) +
             * L-R em torno de 38kHz ainda intactos. */
            fm_demod_process(&fm_demod, stage1_i, stage1_q, stage1_count, audio_pre);

            fm_stereo_pilot_process(&stereo_pilot, audio_pre, stage1_count, cos2wt, NULL, cos3wt, sin3wt);
            int locked = fm_stereo_pilot_locked(&stereo_pilot);
            atomic_store_explicit(&g_state.stereo_locked, locked, memory_order_relaxed);
            atomic_store_explicit(&g_state.pilot_level, fm_stereo_pilot_amplitude(&stereo_pilot),
                                   memory_order_relaxed);

            /* RDS: precisa rodar AQUI, com audio_pre ainda intacto (MPX
             * cru) — o loop de blend logo abaixo reaproveita audio_pre
             * in-place como L, o que destruiria a entrada do RDS se
             * chamado depois. Só decodifica com o piloto travado (RDS é
             * coerente com o piloto por definição do padrão). */
            if (rds_decoder) {
                int rds_enabled = atomic_load_explicit(&g_state.rds_enabled, memory_order_relaxed);
                if (locked && rds_enabled) {
                    rds_decoder_process(rds_decoder, audio_pre, cos3wt, sin3wt, stage1_count);
                    rds_snapshot_t snap;
                    rds_decoder_snapshot(rds_decoder, &snap);
                    pthread_mutex_lock(&g_state.rds_lock);
                    g_state.rds_snapshot = snap;
                    pthread_mutex_unlock(&g_state.rds_lock);
                } else {
                    /* Sem lock do piloto (ou desabilitado pelo usuário):
                     * não alimenta o decodificador, só reporta
                     * sync_locked=0 — mantém PI/PS/RadioText já
                     * decodificados como estavam (uma queda breve de lock
                     * não deveria apagar o nome da estação da tela). */
                    pthread_mutex_lock(&g_state.rds_lock);
                    g_state.rds_snapshot.sync_locked = 0;
                    pthread_mutex_unlock(&g_state.rds_lock);
                }
            }

            int stereo_enabled = atomic_load_explicit(&g_state.stereo_enabled, memory_order_relaxed);
            float target_blend = (locked && stereo_enabled) ? 1.0f : 0.0f;

            /* Demux L/R por amostra + rampa suave mono<->estéreo (blend,
             * one-pole igual à de-ênfase) — evita corte abrupto ao
             * ganhar/perder lock. blend=0 reproduz exatamente o pipeline
             * mono de antes (L=R=L+R, sem perda de 6dB); blend=1 é o
             * demux clássico L=(Σ+Δ)/2, R=(Σ-Δ)/2. audio_pre/mpx_diff são
             * reaproveitados in-place como L/R — seguro porque o índice k
             * é lido antes de ser sobrescrito, sem dependência entre k's. */
            for (size_t k = 0; k < stage1_count; k++) {
                blend += blend_alpha * (target_blend - blend);
                float lr_sum = audio_pre[k];
                float lr_diff = 2.0f * lr_sum * cos2wt[k];
                float l = lr_sum * (1.0f - 0.5f * blend) + 0.5f * blend * lr_diff;
                float r = lr_sum * (1.0f - 0.5f * blend) - 0.5f * blend * lr_diff;
                audio_pre[k] = l;
                mpx_diff[k] = r;
            }

            audio_count = fir_decimator_process(&audio_stage, audio_pre, mpx_diff, stage1_count, audio_out,
                                                 audio_out_r, WORK_CAPACITY);
            if (audio_count > 0) {
                deemphasis_process(&deemph_l, audio_out, audio_count, audio_out);
                deemphasis_process(&deemph_r, audio_out_r, audio_count, audio_out_r);
            }
        }

        if (audio_count == 0) {
            continue;
        }

        size_t pcm_sample_count = audio_count * (size_t)channel_count;

        if (!squelch_open) {
            memset(pcm_out, 0, pcm_sample_count * sizeof(int16_t));
            atomic_store_explicit(&g_state.audio_level_dbfs, -90.0f, memory_order_relaxed);
        } else {
            float peak = 0.0f;
            if (channel_count == 2) {
                for (size_t k = 0; k < audio_count; k++) {
                    float l = clamp_unit(audio_out[k]);
                    float r = clamp_unit(audio_out_r[k]);
                    pcm_out[2 * k] = (int16_t)(l * 32767.0f);
                    pcm_out[2 * k + 1] = (int16_t)(r * 32767.0f);
                    float abs_l = fabsf(l);
                    float abs_r = fabsf(r);
                    if (abs_l > peak) peak = abs_l;
                    if (abs_r > peak) peak = abs_r;
                }
            } else {
                for (size_t k = 0; k < audio_count; k++) {
                    float sample = clamp_unit(audio_out[k]);
                    pcm_out[k] = (int16_t)(sample * 32767.0f);
                    float abs_sample = fabsf(sample);
                    if (abs_sample > peak) peak = abs_sample;
                }
            }
            float dbfs = (peak > 1e-6f) ? 20.0f * log10f(peak) : -90.0f;
            atomic_store_explicit(&g_state.audio_level_dbfs, dbfs, memory_order_relaxed);
        }

        ring_buffer_write(&g_state.pcm_ring, (const uint8_t *)pcm_out, pcm_sample_count * sizeof(int16_t));

        /* Grava o mesmo PCM que acabou de ir pro pcm_ring (tap, não
         * ring buffer separado nem thread própria — ver rtlsdr_shim.h). O
         * check do atomic fora do lock é só uma otimização pra não pagar
         * mutex toda iteração quando não está gravando; a correção contra
         * a corrida com shim_stop_recording vem do re-check de
         * record_writer != NULL já dentro do lock. O canal do wav_writer
         * foi fixado em shim_start_recording lendo audio_channel_count
         * naquele momento — consistente aqui porque a UI (device_screen.dart)
         * sempre para uma gravação em andamento antes de trocar de modo. */
        if (atomic_load_explicit(&g_state.recording_active, memory_order_relaxed)) {
            pthread_mutex_lock(&g_state.record_lock);
            if (g_state.record_writer && wav_writer_write(g_state.record_writer, pcm_out, audio_count) == 0) {
                atomic_fetch_add_explicit(&g_state.recording_bytes_written, pcm_sample_count * sizeof(int16_t),
                                           memory_order_relaxed);
            }
            pthread_mutex_unlock(&g_state.record_lock);
        }
    }

    audio_sink_stop();
    if (rds_decoder) {
        rds_decoder_destroy(rds_decoder);
    }
    fir_decimator_destroy(&iq_stage);
    fir_decimator_destroy(&audio_stage);
    if (spectrum_ok) {
        spectrum_fft_destroy(&spectrum);
    }
    atomic_store_explicit(&g_state.spectrum_valid, 0, memory_order_relaxed);

    while (ring_buffer_read(&g_state.iq_ring, raw, sizeof(raw)) > 0) {
        /* drena o restante para não deixar overflow residual após o stop */
    }
    return NULL;
}

int32_t shim_open_with_fd(int32_t usb_fd, int32_t vendor_id, int32_t product_id) {
    (void)vendor_id;  /* reservado para futuras diferenças por dongle */
    (void)product_id;

    pthread_mutex_lock(&g_state.lock);
    if (atomic_load(&g_state.is_open)) {
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_ALREADY_OPEN;
    }

    libusb_context *ctx = NULL;
    struct libusb_init_option opts[1];
    opts[0].option = LIBUSB_OPTION_NO_DEVICE_DISCOVERY;
    opts[0].value.ival = 0;
    int r = libusb_init_context(&ctx, opts, 1);
    if (r != LIBUSB_SUCCESS) {
        LOGE("libusb_init_context falhou: %d", r);
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_USB_WRAP_FAILED;
    }

    libusb_device_handle *devh = NULL;
    r = libusb_wrap_sys_device(ctx, (intptr_t)usb_fd, &devh);
    if (r != LIBUSB_SUCCESS || devh == NULL) {
        LOGE("libusb_wrap_sys_device falhou: %d", r);
        libusb_exit(ctx);
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_USB_WRAP_FAILED;
    }

    rtlsdr_dev_t *rtl_dev = NULL;
    r = rtlsdr_open_fd(&rtl_dev, ctx, devh);
    if (r < 0) {
        /* rtlsdr_open_fd() já fecha devh/ctx internamente no caminho de
         * erro (mesmo cleanup de rtlsdr_open() original) — não repetir
         * aqui, senão é double-close/use-after-free. */
        LOGE("rtlsdr_open_fd falhou: %d", r);
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_RTLSDR_INIT_FAILED;
    }

    if (ring_buffer_init(&g_state.iq_ring, IQ_RING_CAPACITY) != 0) {
        LOGE("ring_buffer_init (IQ) falhou");
        rtlsdr_close(rtl_dev); /* fecha devh + ctx + libera dev internamente */
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_RTLSDR_INIT_FAILED;
    }
    if (ring_buffer_init(&g_state.pcm_ring, PCM_RING_CAPACITY) != 0) {
        LOGE("ring_buffer_init (PCM) falhou");
        ring_buffer_destroy(&g_state.iq_ring);
        rtlsdr_close(rtl_dev);
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_RTLSDR_INIT_FAILED;
    }

    g_state.usb_ctx = ctx;
    g_state.usb_devh = devh;
    g_state.rtl_dev = rtl_dev;
    g_state.sample_rate_hz = DEFAULT_SAMPLE_RATE_HZ;
    g_state.frequency_hz = DEFAULT_FREQUENCY_HZ;
    atomic_store(&g_state.iq_bytes_received, 0);
    atomic_store(&g_state.ring_overflow_count, 0);
    atomic_store(&g_state.demod_mode, DEMOD_WFM);
    atomic_store(&g_state.squelch_threshold_db, DEFAULT_SQUELCH_THRESHOLD_DB);
    atomic_store(&g_state.rf_level_dbfs, -120.0f);
    atomic_store(&g_state.squelch_open, 1);
    atomic_store(&g_state.stereo_enabled, 1);
    atomic_store(&g_state.stereo_locked, 0);
    atomic_store(&g_state.pilot_level, 0.0f);
    atomic_store(&g_state.audio_channel_count, 1);
    atomic_store(&g_state.rds_enabled, 1);

    rtlsdr_set_sample_rate(rtl_dev, DEFAULT_SAMPLE_RATE_HZ);
    rtlsdr_set_center_freq(rtl_dev, DEFAULT_FREQUENCY_HZ);
    rtlsdr_set_tuner_gain_mode(rtl_dev, 0); /* AGC automático por padrão até o M4 */

    atomic_store(&g_state.is_open, 1);
    pthread_mutex_unlock(&g_state.lock);

    LOGI("Dongle aberto com sucesso via fd %d", usb_fd);
    return SHIM_OK;
}

/* Fecha e finaliza (header WAV corrigido) uma gravação em andamento, se
 * houver. Usada tanto por shim_stop_recording() quanto por
 * shim_stop_streaming()/shim_close() — parar o streaming não pode deixar
 * um WAV com tamanhos zerados pendurado nem a flag recording_active presa
 * em 1 (o que travaria uma tentativa futura de shim_start_recording).
 * Retorna 1 se havia gravação ativa (e foi finalizada), 0 caso contrário. */
static int stop_recording_if_active(void) {
    pthread_mutex_lock(&g_state.record_lock);
    if (!atomic_load(&g_state.recording_active)) {
        pthread_mutex_unlock(&g_state.record_lock);
        return 0;
    }
    wav_writer_t *writer = g_state.record_writer;
    g_state.record_writer = NULL;
    atomic_store(&g_state.recording_active, 0);
    pthread_mutex_unlock(&g_state.record_lock);

    wav_writer_close(writer); /* fora do lock — fseek/fclose não precisa bloquear a dsp_thread */
    return 1;
}

int32_t shim_stop_streaming(void) {
    pthread_mutex_lock(&g_state.lock);
    if (!atomic_load(&g_state.is_streaming)) {
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_NOT_STREAMING;
    }
    rtlsdr_dev_t *rtl_dev = g_state.rtl_dev;
    pthread_t usb_thread = g_state.usb_thread;
    pthread_t dsp_thread = g_state.dsp_thread;
    atomic_store(&g_state.stop_requested, 1);
    pthread_mutex_unlock(&g_state.lock);

    if (rtl_dev) {
        rtlsdr_cancel_async(rtl_dev);
    }
    pthread_join(usb_thread, NULL);
    pthread_join(dsp_thread, NULL);

    pthread_mutex_lock(&g_state.lock);
    atomic_store(&g_state.is_streaming, 0);
    pthread_mutex_unlock(&g_state.lock);

    stop_recording_if_active();
    return SHIM_OK;
}

int32_t shim_close(void) {
    if (atomic_load(&g_state.is_streaming)) {
        shim_stop_streaming();
    }

    pthread_mutex_lock(&g_state.lock);
    if (!atomic_load(&g_state.is_open)) {
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_NOT_OPEN;
    }

    rtlsdr_close(g_state.rtl_dev); /* fecha devh + ctx + libera dev internamente */
    ring_buffer_destroy(&g_state.iq_ring);
    ring_buffer_destroy(&g_state.pcm_ring);

    g_state.rtl_dev = NULL;
    g_state.usb_ctx = NULL;
    g_state.usb_devh = NULL;
    atomic_store(&g_state.is_open, 0);

    pthread_mutex_unlock(&g_state.lock);
    LOGI("Dongle fechado");
    return SHIM_OK;
}

int32_t shim_is_open(void) {
    return atomic_load(&g_state.is_open) ? 1 : 0;
}

int32_t shim_set_frequency_hz(uint32_t freq_hz) {
    pthread_mutex_lock(&g_state.lock);
    if (!atomic_load(&g_state.is_open)) {
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_NOT_OPEN;
    }
    int r = rtlsdr_set_center_freq(g_state.rtl_dev, freq_hz);
    if (r == 0) {
        g_state.frequency_hz = freq_hz;
    }
    pthread_mutex_unlock(&g_state.lock);
    return (r == 0) ? SHIM_OK : SHIM_ERR_INVALID_ARG;
}

uint32_t shim_get_frequency_hz(void) {
    pthread_mutex_lock(&g_state.lock);
    uint32_t freq = g_state.frequency_hz;
    pthread_mutex_unlock(&g_state.lock);
    return freq;
}

int32_t shim_set_sample_rate_hz(uint32_t rate_hz) {
    pthread_mutex_lock(&g_state.lock);
    if (!atomic_load(&g_state.is_open)) {
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_NOT_OPEN;
    }
    if (atomic_load(&g_state.is_streaming)) {
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_ALREADY_STREAMING;
    }
    int r = rtlsdr_set_sample_rate(g_state.rtl_dev, rate_hz);
    if (r == 0) {
        g_state.sample_rate_hz = rate_hz;
    }
    pthread_mutex_unlock(&g_state.lock);
    return (r == 0) ? SHIM_OK : SHIM_ERR_INVALID_ARG;
}

uint32_t shim_get_sample_rate_hz(void) {
    pthread_mutex_lock(&g_state.lock);
    uint32_t rate = g_state.sample_rate_hz;
    pthread_mutex_unlock(&g_state.lock);
    return rate;
}

int32_t shim_set_gain_mode(int32_t auto_gain) {
    pthread_mutex_lock(&g_state.lock);
    if (!atomic_load(&g_state.is_open)) {
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_NOT_OPEN;
    }
    int r = rtlsdr_set_tuner_gain_mode(g_state.rtl_dev, auto_gain ? 0 : 1);
    pthread_mutex_unlock(&g_state.lock);
    return (r == 0) ? SHIM_OK : SHIM_ERR_INVALID_ARG;
}

int32_t shim_set_gain_tenth_db(int32_t gain_tenths_db) {
    pthread_mutex_lock(&g_state.lock);
    if (!atomic_load(&g_state.is_open)) {
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_NOT_OPEN;
    }
    /* Definir um ganho específico só faz sentido em modo manual. */
    rtlsdr_set_tuner_gain_mode(g_state.rtl_dev, 1);
    int r = rtlsdr_set_tuner_gain(g_state.rtl_dev, gain_tenths_db);
    pthread_mutex_unlock(&g_state.lock);
    return (r == 0) ? SHIM_OK : SHIM_ERR_INVALID_ARG;
}

int32_t shim_get_gain_list(int32_t *out_tenths_db, int32_t max_count) {
    if (!out_tenths_db || max_count <= 0) {
        return SHIM_ERR_INVALID_ARG;
    }
    pthread_mutex_lock(&g_state.lock);
    if (!atomic_load(&g_state.is_open)) {
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_NOT_OPEN;
    }

    int count = rtlsdr_get_tuner_gains(g_state.rtl_dev, NULL);
    if (count <= 0) {
        pthread_mutex_unlock(&g_state.lock);
        return 0;
    }

    int *gains = (int *)malloc(sizeof(int) * (size_t)count);
    if (!gains) {
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_INVALID_ARG;
    }
    rtlsdr_get_tuner_gains(g_state.rtl_dev, gains);

    int32_t written = (count < max_count) ? count : max_count;
    for (int32_t i = 0; i < written; i++) {
        out_tenths_db[i] = gains[i];
    }
    free(gains);

    pthread_mutex_unlock(&g_state.lock);
    return written;
}

int32_t shim_set_demod_mode(int32_t mode) {
    if (mode != DEMOD_WFM && mode != DEMOD_NFM && mode != DEMOD_AM) {
        return SHIM_ERR_INVALID_ARG;
    }
    atomic_store_explicit(&g_state.demod_mode, mode, memory_order_relaxed);
    return SHIM_OK;
}

int32_t shim_get_demod_mode(void) {
    return atomic_load_explicit(&g_state.demod_mode, memory_order_relaxed);
}

int32_t shim_set_squelch_threshold_db(float threshold_db) {
    atomic_store_explicit(&g_state.squelch_threshold_db, threshold_db, memory_order_relaxed);
    return SHIM_OK;
}

int32_t shim_set_stereo_enabled(int32_t enabled) {
    atomic_store_explicit(&g_state.stereo_enabled, enabled ? 1 : 0, memory_order_relaxed);
    return SHIM_OK;
}

int32_t shim_set_rds_enabled(int32_t enabled) {
    atomic_store_explicit(&g_state.rds_enabled, enabled ? 1 : 0, memory_order_relaxed);
    return SHIM_OK;
}

int32_t shim_get_rds_info(shim_rds_info_t *out) {
    if (!out) {
        return SHIM_ERR_INVALID_ARG;
    }
    pthread_mutex_lock(&g_state.rds_lock);
    out->pi_code = g_state.rds_snapshot.pi_code;
    out->pty = g_state.rds_snapshot.pty;
    out->tp = g_state.rds_snapshot.tp;
    out->ta = g_state.rds_snapshot.ta;
    memcpy(out->ps, g_state.rds_snapshot.ps, sizeof(out->ps));
    memcpy(out->radiotext, g_state.rds_snapshot.radiotext, sizeof(out->radiotext));
    out->generation = g_state.rds_snapshot.generation;
    out->valid_group_count = g_state.rds_snapshot.valid_group_count;
    out->sync_locked = g_state.rds_snapshot.sync_locked;
    pthread_mutex_unlock(&g_state.rds_lock);
    return SHIM_OK;
}

int32_t shim_start_streaming(void) {
    pthread_mutex_lock(&g_state.lock);
    if (!atomic_load(&g_state.is_open)) {
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_NOT_OPEN;
    }
    if (atomic_load(&g_state.is_streaming)) {
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_ALREADY_STREAMING;
    }

    ring_buffer_reset(&g_state.iq_ring);
    ring_buffer_reset(&g_state.pcm_ring);
    atomic_store(&g_state.iq_bytes_received, 0);
    atomic_store(&g_state.ring_overflow_count, 0);
    atomic_store(&g_state.audio_level_dbfs, -90.0f);
    atomic_store(&g_state.spectrum_valid, 0);
    atomic_store(&g_state.stop_requested, 0);

    /* Descarta PI/PS/RadioText de uma sessão anterior — não deveria
     * sobreviver a um stop/start (troca de estação, por exemplo). */
    pthread_mutex_lock(&g_state.rds_lock);
    memset(&g_state.rds_snapshot, 0, sizeof(g_state.rds_snapshot));
    pthread_mutex_unlock(&g_state.rds_lock);

    int r = pthread_create(&g_state.dsp_thread, NULL, dsp_thread_main, NULL);
    if (r != 0) {
        LOGE("Falha ao criar dsp_thread: %d", r);
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_THREAD_FAILED;
    }
    r = pthread_create(&g_state.usb_thread, NULL, usb_thread_main, NULL);
    if (r != 0) {
        LOGE("Falha ao criar usb_thread: %d", r);
        atomic_store(&g_state.stop_requested, 1);
        pthread_join(g_state.dsp_thread, NULL);
        pthread_mutex_unlock(&g_state.lock);
        return SHIM_ERR_THREAD_FAILED;
    }

    atomic_store(&g_state.is_streaming, 1);
    pthread_mutex_unlock(&g_state.lock);
    return SHIM_OK;
}

int32_t shim_is_streaming(void) {
    return atomic_load(&g_state.is_streaming) ? 1 : 0;
}

int32_t shim_get_stats(shim_stats_t *out) {
    if (!out) {
        return SHIM_ERR_INVALID_ARG;
    }
    out->iq_bytes_received = atomic_load_explicit(&g_state.iq_bytes_received, memory_order_relaxed);
    out->ring_overflow_count = atomic_load_explicit(&g_state.ring_overflow_count, memory_order_relaxed);
    out->rf_level_dbfs = atomic_load_explicit(&g_state.rf_level_dbfs, memory_order_relaxed);
    out->audio_level_dbfs = atomic_load_explicit(&g_state.audio_level_dbfs, memory_order_relaxed);
    out->squelch_open = atomic_load_explicit(&g_state.squelch_open, memory_order_relaxed);
    out->recording_bytes_written = atomic_load_explicit(&g_state.recording_bytes_written, memory_order_relaxed);
    out->stereo_locked = atomic_load_explicit(&g_state.stereo_locked, memory_order_relaxed);
    out->pilot_level = atomic_load_explicit(&g_state.pilot_level, memory_order_relaxed);
    return SHIM_OK;
}

int32_t shim_get_spectrum_db(float *out_mag_db, int32_t num_bins) {
    if (!out_mag_db || num_bins <= 0 || num_bins > SPECTRUM_FFT_SIZE) {
        return SHIM_ERR_INVALID_ARG;
    }
    if (!atomic_load_explicit(&g_state.spectrum_valid, memory_order_relaxed)) {
        return 0;
    }

    pthread_mutex_lock(&g_state.spectrum_lock);
    if (num_bins == SPECTRUM_FFT_SIZE) {
        memcpy(out_mag_db, g_state.spectrum_snapshot, sizeof(float) * (size_t)num_bins);
    } else {
        /* downsample por média simples (bin-averaging) pro num_bins pedido */
        for (int32_t i = 0; i < num_bins; i++) {
            int start = (int)((int64_t)i * SPECTRUM_FFT_SIZE / num_bins);
            int end = (int)((int64_t)(i + 1) * SPECTRUM_FFT_SIZE / num_bins);
            if (end <= start) {
                end = start + 1;
            }
            float sum = 0.0f;
            int count = 0;
            for (int k = start; k < end && k < SPECTRUM_FFT_SIZE; k++) {
                sum += g_state.spectrum_snapshot[k];
                count++;
            }
            out_mag_db[i] = (count > 0) ? (sum / (float)count) : -180.0f;
        }
    }
    pthread_mutex_unlock(&g_state.spectrum_lock);
    return num_bins;
}

int32_t shim_start_recording(const char *file_path) {
    if (!file_path) {
        return SHIM_ERR_INVALID_ARG;
    }
    if (!atomic_load(&g_state.is_streaming)) {
        return SHIM_ERR_NOT_STREAMING;
    }

    pthread_mutex_lock(&g_state.record_lock);
    if (atomic_load(&g_state.recording_active)) {
        pthread_mutex_unlock(&g_state.record_lock);
        return SHIM_ERR_RECORDING_ACTIVE;
    }

    /* Canal atual (1 mono NFM/AM, 2 estéreo WFM — sempre 2 em WFM mesmo
     * sem lock de piloto, ver audio_channel_count em dsp_thread_main) a
     * AUDIO_TARGET_HZ, o mesmo formato do pcm_out que a dsp_thread já está
     * produzindo. Consistente com o resto da gravação porque a UI
     * (device_screen.dart) sempre para uma gravação em andamento antes de
     * trocar de modo — não fica gravando com o canal errado a meio de uma
     * troca WFM<->NFM/AM. */
    int channels = atomic_load_explicit(&g_state.audio_channel_count, memory_order_relaxed);
    if (channels != 1 && channels != 2) {
        channels = 1;
    }
    wav_writer_t *writer = wav_writer_open(file_path, AUDIO_TARGET_HZ, channels);
    if (!writer) {
        pthread_mutex_unlock(&g_state.record_lock);
        LOGE("shim_start_recording: falha ao abrir '%s'", file_path);
        return SHIM_ERR_RECORDING_OPEN_FAILED;
    }

    g_state.record_writer = writer;
    atomic_store(&g_state.recording_bytes_written, 0);
    atomic_store(&g_state.recording_active, 1);
    pthread_mutex_unlock(&g_state.record_lock);
    return SHIM_OK;
}

int32_t shim_stop_recording(void) {
    return stop_recording_if_active() ? SHIM_OK : SHIM_ERR_NOT_RECORDING;
}

int32_t shim_is_recording(void) {
    return atomic_load(&g_state.recording_active) ? 1 : 0;
}
