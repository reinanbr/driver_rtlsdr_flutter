#include "rds_decoder.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "fir_decimator.h"

#define RDS_PI 3.14159265358979323846f

/* Front-end: downconversão + decimação do MPX (256kHz) pro baseband RDS.
 * decim=16 a partir de 256000Hz dá 16000Hz exatos (~6.7 amostras/chip a
 * 2375Hz de taxa de chip) — oversampling confortável pro Gardner com
 * interpolação linear. */
#define RDS_MPX_DECIM 16
#define RDS_FIR_NUM_TAPS 129 /* mais taps que os outros estágios — corte relativo bem mais estreito, ver AVISO no .h */
#define RDS_LOWPASS_CUTOFF_NORMALIZED 0.025f /* ~3.2kHz a 256kHz de entrada, aperta a banda de ~2.4kHz do RDS */

#define RDS_CHIP_RATE_HZ 2375.0f /* = 19000/8 = 2x a taxa de bit (1187.5) */

/* Cobre o WORK_CAPACITY de rtlsdr_shim.c (2048) — count nunca deveria
 * passar disso na prática (mesmo stage1_count usado por fm_stereo_pilot),
 * clampado defensivamente em rds_decoder_process caso passe. */
#define RDS_MIX_CAPACITY 2048
#define RDS_DECIM_CAPACITY 256 /* >= RDS_MIX_CAPACITY/RDS_MPX_DECIM, com folga */

#define GARDNER_LOOP_GAIN 0.02f
#define COSTAS_LOOP_BW_HZ 30.0f
#define COSTAS_ZETA 0.707f

#define RDS_MAX_CONSECUTIVE_BLOCK_ERRORS 4
/* ~44s a 1187.5bps sem conseguir travar sincronismo de bloco — tenta a
 * paridade oposta do par biphase (ver AVISO no .h sobre a ambiguidade de
 * qual chip do par vem primeiro). */
#define RDS_ACQUIRE_TIMEOUT_BITS (26L * 2000L)

typedef enum {
    RDS_OFF_NONE = -1,
    RDS_OFF_A = 0,
    RDS_OFF_B = 1,
    RDS_OFF_C = 2,
    RDS_OFF_CP = 3,
    RDS_OFF_D = 4,
} rds_offset_t;

struct rds_decoder {
    /* front-end: downconversão + decimação */
    fir_decimator_t rds_decim;
    float mix_i[RDS_MIX_CAPACITY];
    float mix_q[RDS_MIX_CAPACITY];
    float dec_i[RDS_DECIM_CAPACITY];
    float dec_q[RDS_DECIM_CAPACITY];

    /* Gardner (timing de chip, 2375Hz) */
    float sps;
    float mu;
    float hist_i[3];
    float hist_q[3];
    int hist_filled;
    float prev_chip_i;
    float prev_chip_q;
    int have_prev_chip;

    /* Costas (fase residual BPSK, por chip) */
    float costas_theta;
    float costas_freq;
    float costas_alpha;
    float costas_beta;

    /* combinação do par biphase (2 chips -> 1 bit bruto) */
    int biphase_slot; /* 0 = esperando o 1º chip do par, 1 = esperando o 2º */
    float biphase_first_i;

    /* decodificação diferencial (bit bruto -> bit de dado) */
    int prev_biphase_bit;
    int have_prev_biphase_bit;

    /* sincronismo de bloco de 26 bits */
    uint32_t reg;
    int sync_locked;
    long unsynced_bit_count;
    int candidate_active;
    int candidate_countdown;
    uint16_t candidate_a_data;
    int block_bit_counter; /* 0..25, só usado enquanto sync_locked */
    int expected_slot;     /* 0..3 = A,B,C/C',D, só usado enquanto sync_locked */
    int consecutive_block_errors;
    uint16_t block_data[4];

    /* resultado decodificado */
    uint16_t pi_code;
    uint8_t pty;
    int tp;
    int ta;
    char ps[9];
    char radiotext[65];
    int last_ab_flag; /* -1 = ainda não visto */
    uint32_t generation;
    uint32_t valid_group_count;
};

/* ---- Sincronismo de bloco: CRC/offset words -------------------------------
 * Matriz de verificação de paridade (26 linhas x 10 bits) e os 5 valores de
 * síndrome A/B/C/C'/D conferidos byte a byte contra redsea
 * (github.com/windytan/redsea, src/block_sync.cc/hh, MIT) — não
 * confiados de memória, ver AVISO em rds_decoder.h. calculateSyndrome é uma
 * tradução direta da função de mesmo nome de lá: bit k (a partir do LSB do
 * registrador de 26 bits, k=0 é o bit mais recente) contribui com a linha
 * [25-k] da matriz. */
static const uint32_t RDS_PARITY_CHECK_MATRIX[26] = {
    0x200, 0x100, 0x080, 0x040, 0x020, 0x010, 0x008, 0x004, 0x002, 0x001,
    0x2DC, 0x16E, 0x0B7, 0x287, 0x39F, 0x313, 0x355, 0x376, 0x1BB, 0x201,
    0x3DC, 0x1EE, 0x0F7, 0x2A7, 0x38F, 0x31B,
};

static uint32_t rds_calc_syndrome(uint32_t block26) {
    uint32_t result = 0;
    for (int k = 0; k < 26; k++) {
        if ((block26 >> k) & 1u) {
            result ^= RDS_PARITY_CHECK_MATRIX[25 - k];
        }
    }
    return result;
}

static rds_offset_t rds_offset_for_syndrome(uint32_t syndrome) {
    switch (syndrome) {
        case 0x3D8: return RDS_OFF_A;  /* 0b1111011000 */
        case 0x3D4: return RDS_OFF_B;  /* 0b1111010100 */
        case 0x25C: return RDS_OFF_C;  /* 0b1001011100 */
        case 0x3CC: return RDS_OFF_CP; /* 0b1111001100 */
        case 0x258: return RDS_OFF_D;  /* 0b1001011000 */
        default: return RDS_OFF_NONE;
    }
}

static int rds_offset_matches_slot(int slot, rds_offset_t actual) {
    switch (slot) {
        case 0: return actual == RDS_OFF_A;
        case 1: return actual == RDS_OFF_B;
        case 2: return actual == RDS_OFF_C || actual == RDS_OFF_CP;
        case 3: return actual == RDS_OFF_D;
        default: return 0;
    }
}

/* ---- Parsing de grupo ------------------------------------------------- */

static void rds_set_ps_chars(rds_decoder_t *d, int pos, char c0, char c1) {
    if (pos < 0 || pos > 6) return;
    int changed = 0;
    if (d->ps[pos] != c0) { d->ps[pos] = c0; changed = 1; }
    if (d->ps[pos + 1] != c1) { d->ps[pos + 1] = c1; changed = 1; }
    if (changed) d->generation++;
}

static void rds_set_rt_chars(rds_decoder_t *d, int pos, char c0, char c1) {
    if (pos < 0 || pos > 62) return;
    int changed = 0;
    if (d->radiotext[pos] != c0) { d->radiotext[pos] = c0; changed = 1; }
    if (d->radiotext[pos + 1] != c1) { d->radiotext[pos + 1] = c1; changed = 1; }
    if (changed) d->generation++;
}

/* Bits exatos (GTYPE b15-12, B0 b11, TP b10, PTY b9-5, PS: TA b4/segmento
 * b1-0, RT: A/B b4/segmento b3-0) conferidos contra a documentação padrão
 * RDS/RBDS e contra station.cc do redsea — ver AVISO em rds_decoder.h. */
static void rds_handle_group(rds_decoder_t *d) {
    uint16_t block_a = d->block_data[0];
    uint16_t block_b = d->block_data[1];
    uint16_t block_c = d->block_data[2];
    uint16_t block_d = d->block_data[3];

    d->pi_code = block_a;
    d->pty = (uint8_t)((block_b >> 5) & 0x1F);
    d->tp = (block_b >> 10) & 0x1;
    int group_type = (block_b >> 12) & 0xF;
    int version_b = (block_b >> 11) & 0x1; /* 0 = versão A, 1 = versão B */

    if (group_type == 0) {
        d->ta = (block_b >> 4) & 0x1;
        int segment = block_b & 0x3;
        rds_set_ps_chars(d, segment * 2, (char)((block_d >> 8) & 0xFF), (char)(block_d & 0xFF));
    } else if (group_type == 2) {
        int ab = (block_b >> 4) & 0x1;
        if (d->last_ab_flag != -1 && ab != d->last_ab_flag) {
            /* A/B alternou: sinaliza troca de texto — limpa o buffer antigo
             * (padrão RDS) em vez de deixar caracteres velhos misturados. */
            memset(d->radiotext, ' ', 64);
            d->generation++;
        }
        d->last_ab_flag = ab;
        int segment = block_b & 0xF;
        if (version_b == 0) {
            /* 2A: 4 chars/grupo — 2 do bloco C, 2 do bloco D. */
            int pos = segment * 4;
            rds_set_rt_chars(d, pos, (char)((block_c >> 8) & 0xFF), (char)(block_c & 0xFF));
            rds_set_rt_chars(d, pos + 2, (char)((block_d >> 8) & 0xFF), (char)(block_d & 0xFF));
        } else {
            /* 2B: só 2 chars/grupo, só do bloco D (bloco C não carrega
             * texto nesse tipo — ver rds_decoder.h). */
            int pos = segment * 2;
            rds_set_rt_chars(d, pos, (char)((block_d >> 8) & 0xFF), (char)(block_d & 0xFF));
        }
    }

    d->valid_group_count++;
}

/* ---- Máquina de estados de sincronismo de bloco ------------------------ */

static void rds_feed_bit(rds_decoder_t *d, int bit) {
    d->reg = ((d->reg << 1) | (uint32_t)(bit & 1)) & 0x3FFFFFFu; /* 26 bits */

    if (!d->sync_locked) {
        d->unsynced_bit_count++;
        if (d->unsynced_bit_count >= RDS_ACQUIRE_TIMEOUT_BITS) {
            d->unsynced_bit_count = 0;
            d->biphase_slot ^= 1; /* tenta a paridade oposta do par biphase */
            d->candidate_active = 0;
        }

        if (d->candidate_active) {
            d->candidate_countdown--;
            if (d->candidate_countdown == 0) {
                uint32_t syn = rds_calc_syndrome(d->reg);
                if (rds_offset_for_syndrome(syn) == RDS_OFF_B) {
                    d->sync_locked = 1;
                    d->block_data[0] = d->candidate_a_data;
                    d->block_data[1] = (uint16_t)((d->reg >> 10) & 0xFFFFu);
                    d->expected_slot = 2;
                    d->consecutive_block_errors = 0;
                    d->block_bit_counter = 0;
                    d->unsynced_bit_count = 0;
                }
                d->candidate_active = 0;
            }
        }
        if (!d->sync_locked && !d->candidate_active) {
            uint32_t syn = rds_calc_syndrome(d->reg);
            if (rds_offset_for_syndrome(syn) == RDS_OFF_A) {
                d->candidate_active = 1;
                d->candidate_countdown = 26;
                d->candidate_a_data = (uint16_t)((d->reg >> 10) & 0xFFFFu);
            }
        }
        return;
    }

    d->block_bit_counter++;
    if (d->block_bit_counter < 26) {
        return;
    }
    d->block_bit_counter = 0;

    uint32_t syn = rds_calc_syndrome(d->reg);
    rds_offset_t actual = rds_offset_for_syndrome(syn);
    if (rds_offset_matches_slot(d->expected_slot, actual)) {
        d->block_data[d->expected_slot] = (uint16_t)((d->reg >> 10) & 0xFFFFu);
        d->consecutive_block_errors = 0;
        d->expected_slot++;
        if (d->expected_slot == 4) {
            d->expected_slot = 0;
            rds_handle_group(d);
        }
    } else {
        d->consecutive_block_errors++;
        if (d->consecutive_block_errors >= RDS_MAX_CONSECUTIVE_BLOCK_ERRORS) {
            d->sync_locked = 0;
            d->candidate_active = 0;
            d->expected_slot = 0;
            d->unsynced_bit_count = 0;
        }
    }
}

/* ---- API pública -------------------------------------------------------- */

rds_decoder_t *rds_decoder_create(float mpx_sample_rate_hz) {
    rds_decoder_t *d = (rds_decoder_t *)calloc(1, sizeof(rds_decoder_t));
    if (!d) {
        return NULL;
    }

    if (fir_decimator_init(&d->rds_decim, RDS_MPX_DECIM, RDS_FIR_NUM_TAPS, RDS_LOWPASS_CUTOFF_NORMALIZED,
                            /*complex_mode=*/1) != 0) {
        free(d);
        return NULL;
    }

    float rds_rate = mpx_sample_rate_hz / (float)RDS_MPX_DECIM;
    d->sps = rds_rate / RDS_CHIP_RATE_HZ;
    d->mu = d->sps;

    float loop_bw = 2.0f * RDS_PI * COSTAS_LOOP_BW_HZ / RDS_CHIP_RATE_HZ;
    float denom = 1.0f + 2.0f * COSTAS_ZETA * loop_bw + loop_bw * loop_bw;
    d->costas_alpha = 4.0f * COSTAS_ZETA * loop_bw / denom;
    d->costas_beta = 4.0f * loop_bw * loop_bw / denom;

    d->last_ab_flag = -1;
    memset(d->ps, ' ', 8);
    d->ps[8] = '\0';
    memset(d->radiotext, ' ', 64);
    d->radiotext[64] = '\0';

    return d;
}

void rds_decoder_destroy(rds_decoder_t *d) {
    if (!d) {
        return;
    }
    fir_decimator_destroy(&d->rds_decim);
    free(d);
}

void rds_decoder_process(rds_decoder_t *d, const float *mpx, const float *cos3wt, const float *sin3wt, size_t count) {
    if (count > RDS_MIX_CAPACITY) {
        count = RDS_MIX_CAPACITY; /* proteção defensiva, não deveria disparar na prática — ver .h */
    }

    for (size_t n = 0; n < count; n++) {
        d->mix_i[n] = mpx[n] * cos3wt[n];
        d->mix_q[n] = mpx[n] * sin3wt[n];
    }

    size_t dec_count =
        fir_decimator_process(&d->rds_decim, d->mix_i, d->mix_q, count, d->dec_i, d->dec_q, RDS_DECIM_CAPACITY);

    for (size_t n = 0; n < dec_count; n++) {
        float bb_i = d->dec_i[n];
        float bb_q = d->dec_q[n];

        d->hist_i[0] = d->hist_i[1];
        d->hist_i[1] = d->hist_i[2];
        d->hist_i[2] = bb_i;
        d->hist_q[0] = d->hist_q[1];
        d->hist_q[1] = d->hist_q[2];
        d->hist_q[2] = bb_q;

        if (d->hist_filled < 3) {
            d->hist_filled++;
            d->mu -= 1.0f;
            continue;
        }

        d->mu -= 1.0f;
        if (d->mu > 0.0f) {
            continue;
        }

        /* Gardner: interpola a amostra "on-time" na posição fracionária
         * alvo (frac, dentro da janela [hist[1], hist[2]]) e ajusta mu com
         * base no erro (aproximação de "mid sample" via ponto médio entre
         * os 2 últimos chips decididos — ver AVISO em rds_decoder.h). */
        float frac = 1.0f + d->mu;
        if (frac < 0.0f) frac = 0.0f;
        if (frac > 1.0f) frac = 1.0f;

        float on_i = d->hist_i[1] + frac * (d->hist_i[2] - d->hist_i[1]);
        float on_q = d->hist_q[1] + frac * (d->hist_q[2] - d->hist_q[1]);

        if (d->have_prev_chip) {
            float mid_i = 0.5f * (on_i + d->prev_chip_i);
            float mid_q = 0.5f * (on_q + d->prev_chip_q);
            float error = mid_i * (on_i - d->prev_chip_i) + mid_q * (on_q - d->prev_chip_q);
            d->mu += d->sps - GARDNER_LOOP_GAIN * error;
        } else {
            d->mu += d->sps;
        }

        /* Costas (BPSK) por chip — corrige rotação de fase residual entre a
         * referência de 3ª harmônica (fm_stereo_pilot) e a fase real do RDS
         * nesta cadeia de decimação. */
        float costas_sin = sinf(d->costas_theta);
        float costas_cos = cosf(d->costas_theta);
        float corrected_i = on_i * costas_cos + on_q * costas_sin;
        float corrected_q = -on_i * costas_sin + on_q * costas_cos;
        float costas_error = (corrected_i >= 0.0f ? 1.0f : -1.0f) * corrected_q;
        d->costas_freq += d->costas_beta * costas_error;
        d->costas_theta += d->costas_freq + d->costas_alpha * costas_error;
        if (d->costas_theta > RDS_PI) {
            d->costas_theta -= 2.0f * RDS_PI;
        } else if (d->costas_theta < -RDS_PI) {
            d->costas_theta += 2.0f * RDS_PI;
        }

        d->prev_chip_i = on_i;
        d->prev_chip_q = on_q;
        d->have_prev_chip = 1;

        /* Combinação do par biphase: 2 chips -> 1 bit bruto (comparação
         * suave entre os dois, não decisão dura dupla). */
        if (d->biphase_slot == 0) {
            d->biphase_first_i = corrected_i;
            d->biphase_slot = 1;
        } else {
            int biphase_bit = (d->biphase_first_i - corrected_i) > 0.0f ? 1 : 0;
            d->biphase_slot = 0;

            if (d->have_prev_biphase_bit) {
                /* Decodificação diferencial — também resolve de graça a
                 * ambiguidade de ±180° do Costas (inverter todos os bits
                 * brutos não muda o XOR consecutivo). */
                int data_bit = biphase_bit ^ d->prev_biphase_bit;
                rds_feed_bit(d, data_bit);
            }
            d->prev_biphase_bit = biphase_bit;
            d->have_prev_biphase_bit = 1;
        }
    }
}

void rds_decoder_snapshot(const rds_decoder_t *d, rds_snapshot_t *out) {
    if (!d || !out) {
        return;
    }
    out->pi_code = d->pi_code;
    out->pty = d->pty;
    out->tp = d->tp;
    out->ta = d->ta;
    memcpy(out->ps, d->ps, sizeof(out->ps));
    memcpy(out->radiotext, d->radiotext, sizeof(out->radiotext));
    out->generation = d->generation;
    out->valid_group_count = d->valid_group_count;
    out->sync_locked = d->sync_locked;
}
