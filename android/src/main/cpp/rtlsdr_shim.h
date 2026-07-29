#ifndef RTLSDR_SHIM_H
#define RTLSDR_SHIM_H

#include <stdint.h>

/*
 * API pública da lib nativa, chamada tanto pelo Dart FFI (dlsym direto,
 * por isso extern "C" sem name mangling) quanto por jni_bridge.cpp.
 *
 * shim_open_with_fd() só deve ser chamada a partir do JNI (jni_bridge.cpp),
 * pois só o lado Kotlin (UsbManager/UsbDeviceConnection) consegue obter um
 * file descriptor USB válido com permissão concedida.
 *
 * Milestone 4: modos de demodulação (WFM/NFM/AM), ganho e squelch. Espectro
 * chega no Milestone 5.
 */

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    SHIM_OK                     = 0,
    SHIM_ERR_ALREADY_OPEN       = -1,
    SHIM_ERR_USB_WRAP_FAILED    = -2,
    SHIM_ERR_RTLSDR_INIT_FAILED = -3,
    SHIM_ERR_NOT_OPEN           = -4,
    SHIM_ERR_INVALID_ARG        = -5,
    SHIM_ERR_ALREADY_STREAMING  = -6,
    SHIM_ERR_NOT_STREAMING      = -7,
    SHIM_ERR_THREAD_FAILED      = -8,
    SHIM_ERR_RECORDING_ACTIVE   = -9,  /* já gravando */
    SHIM_ERR_NOT_RECORDING      = -10, /* shim_stop_recording sem gravação ativa */
    SHIM_ERR_RECORDING_OPEN_FAILED = -11,
} shim_status_t;

typedef enum {
    DEMOD_WFM = 0,
    DEMOD_NFM = 1,
    DEMOD_AM  = 2,
} demod_mode_t;

/* ---- Ciclo de vida ------------------------------------------------- */

int32_t shim_open_with_fd(int32_t usb_fd, int32_t vendor_id, int32_t product_id);
int32_t shim_close(void);
int32_t shim_is_open(void);

/* ---- Sintonia -------------------------------------------------------- */

int32_t shim_set_frequency_hz(uint32_t freq_hz);
uint32_t shim_get_frequency_hz(void);
int32_t shim_set_sample_rate_hz(uint32_t rate_hz);
uint32_t shim_get_sample_rate_hz(void);

/* ---- Ganho -------------------------------------------------------------
 * Valores de ganho em décimos de dB (convenção da própria librtlsdr), ex.
 * 40 = 4.0 dB. */

int32_t shim_set_gain_mode(int32_t auto_gain); /* 1 = AGC automático, 0 = manual */
/* Define o ganho manual (também muda pra modo manual automaticamente). */
int32_t shim_set_gain_tenth_db(int32_t gain_tenths_db);
/* Preenche out_tenths_db (até max_count) com os ganhos suportados pelo
 * tuner; retorna quantos foram escritos (ou < 0 em erro). */
int32_t shim_get_gain_list(int32_t *out_tenths_db, int32_t max_count);

/* ---- Demodulação / squelch --------------------------------------------
 * Mudar o modo só tem efeito no próximo shim_start_streaming() (a thread
 * de DSP lê o modo uma vez ao iniciar) — trocar de modo com streaming
 * ativo exige parar e iniciar de novo. Squelch só se aplica a NFM/AM;
 * WFM ignora (rádio comercial não teria squelch, é sempre "aberto"). */

int32_t shim_set_demod_mode(int32_t mode /* demod_mode_t */);
int32_t shim_get_demod_mode(void);
int32_t shim_set_squelch_threshold_db(float threshold_db);

/* ---- Estéreo (WFM) -----------------------------------------------------
 * Diferente de demod_mode, aplicado ao vivo (a thread de DSP lê o atomic a
 * cada bloco) — não precisa parar/reiniciar o streaming pra trocar. Não
 * força stream mono no hardware/Oboe quando desligado: só controla o blend
 * L/R (ver rtlsdr_shim.c), o stream de saída continua estéreo em WFM
 * (canais idênticos = mono percebido) pra não reabrir o Oboe a cada toggle.
 * `stereo_locked` em shim_stats_t reflete se o piloto de 19kHz está
 * detectado no sinal, independente deste toggle. */
int32_t shim_set_stereo_enabled(int32_t enabled);

/* ---- RDS (WFM) -----------------------------------------------------------
 * Só decodifica com o piloto estéreo travado (RDS é coerente com o piloto
 * por definição do padrão — ver dsp/rds_decoder.h). Aplicado ao vivo, como
 * o toggle de estéreo. `sync_locked` aqui é o sincronismo de BLOCO RDS
 * (26 bits, CRC/offset word) — independente de `stereo_locked` em
 * shim_stats_t (piloto de 19kHz), embora dependa dele pra sequer começar a
 * tentar. */
int32_t shim_set_rds_enabled(int32_t enabled);

typedef struct {
    uint16_t pi_code;
    uint8_t  pty;
    int32_t  tp;
    int32_t  ta;
    char     ps[9];         /* 8 chars + NUL, preenchido progressivamente */
    char     radiotext[65]; /* 64 chars + NUL, preenchido progressivamente */
    uint32_t generation;    /* incrementa sempre que ps/radiotext mudam de fato —
                              * Dart pode usar isso pra evitar diffar strings */
    uint32_t valid_group_count;
    int32_t  sync_locked;
} shim_rds_info_t;

int32_t shim_get_rds_info(shim_rds_info_t *out);

/* ---- Streaming -------------------------------------------------------- */

int32_t shim_start_streaming(void);
int32_t shim_stop_streaming(void);
int32_t shim_is_streaming(void);

/* ---- Telemetria (Dart faz polling periódico) -------------------------- */

typedef struct {
    uint64_t iq_bytes_received;
    uint32_t ring_overflow_count;
    float    rf_level_dbfs;
    float    audio_level_dbfs;
    int32_t  squelch_open;
    uint64_t recording_bytes_written; /* 0 se não estiver gravando */
    int32_t  stereo_locked;           /* piloto de 19kHz detectado (só significativo em WFM) */
    float    pilot_level;             /* amplitude do piloto (unidade arbitrária, só útil relativa) */
} shim_stats_t;

int32_t shim_get_stats(shim_stats_t *out);

/* ---- Gravação -----------------------------------------------------------
 * Grava o mesmo PCM que já vai pro alto-falante (tap logo antes do
 * ring_buffer_write do pcm_ring, dentro da thread de DSP) direto num WAV
 * em `file_path` (caminho completo, já deve existir o diretório-pai —
 * responsabilidade do chamador Dart, que tem acesso a path_provider).
 * Exige streaming ativo (shim_start_streaming já chamado). Parar o
 * streaming finaliza automaticamente uma gravação em andamento (fecha o
 * WAV com os tamanhos corrigidos) — não fica um arquivo com header zerado
 * pendurado. */
int32_t shim_start_recording(const char *file_path);
int32_t shim_stop_recording(void);
int32_t shim_is_recording(void);

/* ---- Espectro (Dart faz polling em ~20-30fps pro waterfall) -----------
 * Snapshot da banda inteira capturada (não o canal estreito do
 * demodulador), calculado sobre IQ bruto pré-decimação. out_mag_db[0] =
 * borda inferior da banda, out_mag_db[num_bins-1] = borda superior — pronto
 * pra desenhar direto. Retorna num_bins em sucesso, 0 se não estiver
 * streaming (sem novo dado ainda). num_bins deve ser <= 1024. */
int32_t shim_get_spectrum_db(float *out_mag_db, int32_t num_bins);

#ifdef __cplusplus
}
#endif

#endif
