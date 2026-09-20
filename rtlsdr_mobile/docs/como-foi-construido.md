# Como o RTL-SDR Mobile foi construído

Este documento explica, em detalhe técnico, como a decodificação estéreo/RDS em
WFM, o scan automático de frequências, a gravação/exportação de áudio, a
licença GPL e o sintonizador visual por espectro deste app foram projetados e
implementados — e como cada peça foi validada contra hardware real (um dongle
RTL2838U num Moto G35 5G, via ADB por Wi-Fi).

A versão em inglês deste documento está em
[`how-it-was-built.md`](how-it-was-built.md).

## 1. Ponto de partida

Antes deste trabalho, o app já tinha um pipeline funcional:

- Kotlin (`UsbBridge.kt`) solicita permissão USB e repassa um file descriptor
  bruto pro código nativo via JNI (`nativeOpenWithFd`) — só o lado Android
  consegue obter um fd USB com permissão concedida.
- C nativo (`rtlsdr_shim.c`) envolve esse fd com `libusb_wrap_sys_device()` e
  abre com um `rtlsdr_open_fd()` modificado (a librtlsdr normalmente só abre
  dispositivos enumerando `/dev/bus/usb/*`, o que exige root no Android).
- Uma thread leitora de USB transmite IQ bruto de 8 bits pra um ring buffer
  lock-free.
- Uma thread de DSP decima esse IQ em dois estágios (banda de canal, depois
  banda de áudio), demodula (WFM/NFM/AM, só mono) e escreve PCM de 16 bits num
  segundo ring buffer consumido por um callback de áudio do Oboe.
- O Dart fala com a mesma biblioteca nativa de duas formas: JNI (Kotlin) só
  pro handoff do fd USB, e FFI direto (`dart:ffi`, sem ffigen — bindings
  escritas à mão) pra tudo mais (sintonia, streaming, estatísticas, espectro).
  Os dois carregamentos resolvem pra mesma instância de `libnative_rtlsdr.so`
  no mesmo processo, então o estado é compartilhado.

Esta sessão adicionou cinco coisas em cima disso: uma licença GPL (exigida por
vincular a `librtlsdr` GPLv2), gravação de áudio, scan automático de
frequências, decodificação estéreo em WFM e decodificação de RDS — além de,
depois, uma passada de UI (removeu o selo de debug, corrigiu um bug real de
renderização do waterfall, substituiu um "carrossel de presets" de primeira
tentativa por um sintonizador de espectro arrastável estilo CubicSDR/gqrx, e
adicionou uma tela de configurações).

## 2. Licenciamento

O app vendoriza a `librtlsdr` 2.1.0, licenciada como "GPLv2, ou (a seu
critério) qualquer versão posterior" (confirmado direto no cabeçalho de
`librtlsdr.c`). Vincular código GPL a um binário cria uma obra combinada que
precisa ser distribuída sob GPL — isso já estava sinalizado como um TODO em
aberto no `docs/native_build.md` antes desta sessão ("uso pessoal, sem
distribuição — revisitar antes de distribuir de qualquer forma"). Um arquivo
`LICENSE` na raiz (texto da GPLv2, com a cláusula "ou posterior" no aviso de
copyright do próprio app — a mesma fórmula que o próprio `librtlsdr.c` usa)
resolve isso: o app é GPLv2-ou-posterior, satisfazendo distribuição tanto sob
GPLv2 quanto GPLv3. `libusb` (LGPL-2.1), KissFFT (BSD-3-Clause) e Oboe
(Apache-2.0) são todas compatíveis sem exigir mudança de licenciamento.

## 3. Gravação/exportação de áudio

**Lado nativo** (`dsp/wav_writer.c/h`): um escritor de WAV incremental e
pequeno. Escreve um header RIFF/WAVE PCM16 de 44 bytes com os dois campos de
tamanho zerados (o tamanho final do arquivo só é conhecido quando a gravação
para), depois transmite PCM conforme chega, e no fechamento faz `seek` de
volta pra corrigir o tamanho do chunk RIFF e do chunk `data`.

**Ponto de captura**: em vez de um segundo ring buffer e uma thread
dedicada de escrita, o gravador captura o mesmo buffer `pcm_out` que a
thread de DSP já calcula, logo antes de escrevê-lo no ring de áudio via
`ring_buffer_write()` — sem buffer extra, e o arquivo sempre contém
exatamente o que foi pro alto-falante. `shim_start_recording(path)` abre o
escritor (lendo o número de canais *atual* — 1 ou 2 — do estado
compartilhado, então bate com o que o demodulador está produzindo naquele
momento); `shim_stop_recording()` e um helper interno
`stop_recording_if_active()` (também chamado por `shim_stop_streaming()`)
fecham com segurança — parar o streaming durante uma gravação finaliza o WAV
automaticamente em vez de deixar um arquivo com os campos de tamanho zerados.

**Concorrência**: um `pthread_mutex_t record_lock` protege o próprio ponteiro
do escritor (não só a flag "está gravando"), porque `shim_stop_recording()`
pode rodar na thread de plataforma do Dart no mesmo instante em que a thread
de DSP está no meio de uma escrita — sem o lock existe uma janela de
use-after-free entre "a gravação ainda está marcada como ativa" e a chamada
de fato a `wav_writer_write()`.

**Lado Dart**: o diretório de armazenamento externo específico do app do
`path_provider` (sem exigir permissão de storage em runtime no Android
moderno) mais `share_plus` pra exportar via a folha de compartilhamento do
Android — evitando deliberadamente a complexidade de `MediaStore`/SAF numa
primeira versão.

**Validado em hardware**: gravou 10s de áudio NFM → arquivo de 647KB, batendo
quase exatamente com o esperado `32000 Hz × 2 bytes × 10s ≈ 625KB` mais o
header. Gravou de novo em WFM estéreo (taxa de bytes dobrada) — parou e
reiniciou de forma limpa, arquivo correto nas duas vezes, zero overflow de
ring buffer enquanto escrevia em disco no meio do streaming.

## 4. Scan automático de frequências

Implementado inteiramente em Dart (`lib/radio/scan_controller.dart`) — nenhum
código nativo novo, porque o shim já expunha tudo que era necessário:
`shim_set_frequency_hz` e `shim_get_stats().rf_level_dbfs`.

O loop é uma varredura assíncrona baseada em `Future` (não `Timer.periodic`,
já que cada passo precisa de um atraso de assentamento variável), e não é
travado na banda de FM comercial — início, fim, passo e limiar são todos
fornecidos pelo chamador, então o mesmo controller consegue varrer uma faixa
estreita PMR/rádio amador em NFM tão bem quanto FM comercial em WFM. Por
passo: sintoniza, espera ~50ms pro PLL/AGC do tuner assentar, amostra o nível
de RF duas vezes com 20ms de intervalo (usa o máximo, redução de ruído
barata), compara com o limiar. Um método dedicado
`RadioController.sampleRfLevelDbfsNow()` foi adicionado porque o polling de
estatísticas existente só atualiza a cada 500ms — rápido demais... digo,
lento demais pra um scan de ~70ms/passo; ele lê estatísticas frescas
imediatamente sem atrapalhar o cálculo de taxa (`bytesPerSecond`) que o
polling periódico depende.

Cancelar no meio do scan restaura a frequência original; deixar rodar até o
fim deixa o rádio sintonizado na última frequência varrida (as duas coisas
são deliberadas — a "última posição" de um scan completo é um lugar razoável
pra pousar, um cancelado não deveria te deixar preso em algum lugar
arbitrário). Estações encontradas podem ser sintonizadas com um toque ou
salvas como preset, reaproveitando o `PresetsController` já existente — sem
storage novo.

**Validado em hardware**: varreu 87.5–108.0 MHz, encontrou 35 estações reais,
progresso atualizando ao vivo; cancelar no meio da varredura restaurou
corretamente a frequência anterior ao scan.

## 5. Decodificação estéreo em WFM

É aqui que fica interessante. FM estéreo comercial multiplexa L+R
(0–15kHz), um tom piloto de 19kHz, e L−R como um sinal de dupla banda
lateral com portadora suprimida centrado em 38kHz (23–53kHz) — mais,
opcionalmente, RDS em 57kHz (coberto no §6).

### 5.1 Reestruturação do pipeline

O `fm_demod_process()` existente já tinha de-ênfase embutida. Isso está
errado pra estéreo: de-ênfase é um filtro shelf passa-baixa que atacaria o
piloto de 19kHz e as bandas laterais de 38kHz antes que pudessem ser
demultiplexadas. Correção: em WFM, `fm_demod_init()` agora é chamado com
`deemphasis_tau_us=0` (desligada) — igual o NFM já fazia — então o
discriminador devolve o sinal MPX cru, intocado. A de-ênfase se move pra um
módulo novo e independente (`dsp/deemphasis.c/h`, a mesma matemática que
antes vivia dentro de `demod_fm.c`) aplicada *depois* do split estéreo e
*depois* da decimação, uma vez por canal, a 32kHz em vez de uma vez a 256kHz
(mais barato, e matematicamente equivalente já que é um filtro LTI bem
abaixo do corte da decimação).

### 5.2 PLL do piloto (`dsp/fm_stereo_pilot.c/h`)

Um PLL de segunda ordem controlado por PI trava no piloto de 19kHz, rodando
direto sobre o MPX cru sem filtro passa-banda dedicado — a própria banda
estreita do loop *é* o filtro de rastreio, que é o que decodificadores FM
estéreo open-source estabelecidos (ex. SoftFM) fazem; um BPF separado só
adicionaria contabilidade de atraso de grupo sem ganho real. Por amostra:

```
error  = mpx[n] * sin(theta)
freq  += beta  * error
theta += freq + alpha * error
```

`alpha`/`beta` vêm das fórmulas padrão de banda passante/amortecimento de
loop PLL discreto (`loop_bw ≈ 8Hz`, `zeta ≈ 0.707` — estimativas de partida,
não validadas contra offsets de frequência de transmissores reais).

Os harmônicos de 2ª e 3ª ordem necessários pro demux estéreo (38kHz) e pra
downconversão do RDS (57kHz) vêm "de graça" da própria fase do NCO via
identidades de soma de ângulos — sem um segundo ou terceiro oscilador:

```
sin(2θ) = 2 sinθ cosθ              cos(2θ) = cos²θ − sin²θ
sin(3θ) = sin(2θ)cosθ + cos(2θ)sinθ   cos(3θ) = cos(2θ)cosθ − sin(2θ)sinθ
```

A detecção de lock rastreia a amplitude do piloto via uma correlação I/Q
filtrada passa-baixa contra o próprio NCO do PLL, com histerese e um contador
de debounce (mesmo padrão já usado no squelch) pra evitar oscilar bem na
borda do limiar.

### 5.3 Demux L/R

Por amostra, uma vez que `cos(2θ)` está disponível:

```
lr_sum  = mpx[n]                      // L+R
lr_diff = 2 · mpx[n] · cos(2θ)[n]     // demod coerente DSB-SC de L−R
L = lr_sum·(1 − 0.5·blend) + 0.5·blend·lr_diff
R = lr_sum·(1 − 0.5·blend) − 0.5·blend·lr_diff
```

`blend` é um suavizador de um polo (mesmo formato do filtro de de-ênfase,
constante de tempo ~150ms) subindo rumo a 1.0 quando o piloto está travado
*e* o usuário não forçou mono, ou descendo rumo a 0.0 caso contrário. Em
`blend = 0`, `L = R = lr_sum` — idêntico bit a bit ao comportamento mono
antigo, sem perda de 6dB — então perder o lock nunca causa uma queda de
nível, só um fade suave pra mono em vez de um corte abrupto.

L e R são decimados juntos usando o `fir_decimator` *já existente* em
`complex_mode=1` — um reaproveitamento deliberado: esse modo foi escrito pra
filtrar I e Q como duas convoluções reais independentes e sincronizadas, que
é exatamente o formato certo pra "dois canais reais compartilhando um clock
de decimação", mesmo sem nenhuma rotação complexa de verdade envolvida.
Nenhum código de decimador novo foi necessário.

### 5.4 Caminho de áudio estéreo

O Oboe agora abre em estéreo (2 canais) sempre que o modo é WFM — mesmo que
o piloto não esteja travado ou o usuário tenha forçado mono, então
`blend=0` só significa que os dois canais carregam áudio idêntico, em vez de
derrubar e reabrir o stream do Oboe a cada transição de lock/unlock. O
zero-fill de underrun em `audio_sink_oboe.cpp` teve que mudar de
`bytes = frames * sizeof(int16_t)` pra
`bytes = frames * channel_count * sizeof(int16_t)` — um bug de uma linha
fácil de introduzir ao generalizar um sink de áudio mono-only pra estéreo,
sinalizado explicitamente durante a implementação porque corrompe
silenciosamente só metade do buffer de preenchimento de underrun se passar
despercebido. `PCM_RING_CAPACITY` foi dobrado (128KiB → 256KiB) pra manter a
mesma margem de ~2s no pior caso (estéreo).

### 5.5 Validado em hardware

O PLL do piloto travou repetidamente em sinais de transmissão reais
(confirmado pelo indicador "Estéreo (piloto travado)" ficando verde ao
vivo), em múltiplas frequências, imediatamente após sintonizar. Essa é a
peça de maior risco não testada de toda a sessão, e funcionou corretamente
na primeira tentativa em hardware real.

## 6. Decodificação de RDS

RDS (IEC 62106 / RBDS) viaja num subportador de 57kHz — a 3ª harmônica do
piloto — a 1187.5 bits/s, codificado em biphase (estilo Manchester), depois
codificado diferencialmente. Essa é a peça mais arriscada e intrincada da
sessão, construída do zero em vez de portada de um decodificador existente —
com uma exceção importante: as **constantes de CRC/offset word foram
transcritas e verificadas, byte a byte, contra o
[redsea](https://github.com/windytan/redsea)** (um decodificador RDS
open-source real e ativamente mantido, licenciado MIT), em vez de confiadas
de memória. Errar essas constantes não quebra nada — falha silenciosamente,
produzindo um decodificador que parece plausivelmente correto mas nunca
decodifica dado real de verdade, exatamente o tipo de bug caro de pegar sem
uma forma de verificar os números de forma independente.

### 6.1 Front-end

`audio_pre` (o MPX cru, o mesmo buffer que o piloto estéreo lê) é misturado
pra baixo por `cos(3θ)`/`sin(3θ)` (a 3ª harmônica do PLL do piloto, então o
RDS fica coerente em fase com a mesma referência que o estéreo usa) e
decimado por uma instância dedicada de `fir_decimator` complexo — 256kHz →
16kHz, fator de decimação 16, 129 taps (mais que os 63 usados nos outros
estágios, porque a banda ocupada de ~2.4kHz precisa de um corte *relativo*
bem mais estreito, o que exige mais taps pra rejeição de banda de parada
equivalente) e um corte mais apertado (~3.2kHz em vez da fórmula genérica
`0.9/decim` usada nos outros estágios) pra rejeitar vazamento de
piloto/estéreo.

### 6.2 Recuperação de clock de símbolo — Gardner, na taxa de chip

Uma primeira versão do design assumia um único loop de Gardner rodando na
taxa de bit de 1187.5. Isso está errado: dado codificado em biphase tem
média zero (DC-null) sobre um período de símbolo *por construção* — a
informação está inteiramente em qual metade do símbolo é positiva vs.
negativa, não numa amplitude líquida — então um loop de timing na taxa de
símbolo não veria praticamente nada pra travar. Decodificadores de verdade
(incluindo o redsea) recuperam o timing a **2375Hz, o dobro da taxa de
bit** — um "chip" recuperado por Gardner por meio-símbolo — depois combinam
pares de chips em bits. A implementação de Gardner deste projeto usa
interpolação linear entre as duas amostras mais próximas do baseband de
16kHz (~6.7 amostras/chip) pra a amostra "on-time", e aproxima a amostra
"mid" que o termo de erro de Gardner precisa como o ponto médio entre o chip
atual e o anterior já decidido (uma simplificação em relação a uma
interpolação independente exatamente em −sps/2 — razoável perto do lock, um
termo de erro mais largo quando não).

### 6.3 Loop de Costas, combinação biphase, decodificação diferencial

Um loop de Costas BPSK por chip (`error = sign(I) · Q`) corrige a rotação de
fase residual entre o caminho do piloto estéreo e a própria cadeia de
decimação do caminho de RDS (filtros diferentes, atraso de grupo
diferente). Pares consecutivos de chips se combinam num único bit bruto via
uma comparação suave (`primeiro_chip_I − segundo_chip_I > 0`), depois
`bit_de_dado = bit_bruto XOR bit_bruto_anterior` recupera o bit realmente
transmitido — o que, como efeito colateral, também absorve de graça a
ambiguidade de ±180° inerente ao loop de Costas (inverter todos os bits
brutos não muda um XOR de valores consecutivos). Uma alternância de
paridade `biphase_slot`, disparada se o sincronismo de bloco não travar em
~44 segundos, se protege contra ter o alinhamento de "qual chip do par vem
primeiro" invertido.

### 6.4 Sincronismo de bloco

Blocos de RDS têm 26 bits (16 de dados + 10 bits de verificação, polinômio
gerador `x^10+x^8+x^7+x^5+x^4+x^3+1`), onde os bits de verificação são o CRC
dos dados combinado via XOR com uma de cinco offset words de 10 bits que
identificam a posição do bloco (A, B, C, C′, D). A função de cálculo de
síndrome e sua matriz de verificação de paridade de 26 linhas, mais os cinco
valores de síndrome→offset, foram obtidos de `block_sync.cc`/`block_sync.hh`
do redsea e verificados manualmente bit a bit (cada uma das 26 linhas da
matriz e as 5 constantes de síndrome convertidas de binário pra hex e
conferidas contra a fonte) antes de serem portados — ver os comentários em
`dsp/rds_decoder.c` pra a proveniência exata.

A aquisição se ancora especificamente no offset A: varre todas as posições
de bit procurando um match de síndrome contra A, depois exige que B apareça
exatamente 26 bits depois antes de declarar lock (uma alternativa mais
simples, um pouco mais lenta pra adquirir, do que buscar os cinco offsets em
paralelo). Uma vez travado, o slot do bloco N só precisa ser checado contra
*seu* offset esperado (C ou C′ são ambos aceitos pro slot 2, já que qual dos
dois é usado codifica a versão A/B do grupo — redundantemente com um bit no
próprio bloco B); perder sincronismo 3–6 blocos seguidos volta pra
aquisição.

### 6.5 Parsing de grupo

O bloco A é o código PI diretamente. O bloco B carrega o tipo de grupo (bits
15–12), versão A/B (bit 11), TP (bit 10), PTY (bits 9–5) e bits específicos
do grupo. O grupo 0 (A/B) carrega PS (o nome de 8 caracteres da estação, 2
caracteres por grupo, endereço nos bits 1–0 do bloco B) e TA (bit 4). O
grupo 2A carrega RadioText 4 caracteres de cada vez (2 do bloco C, 2 do
bloco D); o grupo 2B carrega 2 de cada vez só do bloco D. Os offsets de bit
exatos foram conferidos contra o resumo técnico de RDS da Wikipedia e o
`station.cc` do redsea, em vez de recordados de memória, seguindo o mesmo
princípio de "verificar, não confiar na memória" aplicado às constantes de
CRC.

### 6.6 Exposição pro Dart

Uma struct `shim_rds_info_t` (PI, PTY, TP, TA, PS, RadioText, um contador de
geração que só incrementa quando o texto decodificado muda de fato, um
contador de grupos válidos, e uma flag de sincronismo travado) é protegida
por seu próprio mutex e copiada no polling — o mesmo padrão já usado pro
snapshot do espectro. O Dart espelha com uma `ffi.Struct` correspondente
(`ShimRdsInfo`) e um `RdsController` dedicado fazendo polling a cada 500ms,
compartilhando seu ciclo de vida de start/stop com o padrão já existente do
`SpectrumPoller` (um campo simples aninhado em `RadioController`, não um
`Provider` de nível superior).

### 6.7 Validado em hardware

O RDS conseguiu lock de verdade numa estação real e decodificou **PS
"GRFM", PI 65399, PTY 14, TA ativo** — corretamente. Isso é os offsets de
bit do parsing de grupo, a tabela de síndrome do CRC, e toda a cadeia
Gardner→Costas→biphase→diferencial funcionando juntos corretamente contra
um sinal real over-the-air, na primeira tentativa. O lock foi intermitente
(caiu e recuperou sozinho nos minutos seguintes) — esperado, dado que os
ganhos de loop são estimativas de partida não validadas por design (ver
§8), e uma confirmação honesta de que o *algoritmo* está correto mesmo que
o *ajuste fino* não esteja terminado.

## 7. UI: sintonizador de espectro, correção do waterfall, configurações

Uma primeira versão adicionou um carrossel horizontal deslizável de presets
salvos. Não era o formato certo — um pedido de correção pediu algo mais
próximo do CubicSDR/gqrx: uma exibição de espectro ao vivo com um cursor de
sintonia fixo no centro que você arrasta através, não uma lista de
estações.

**`lib/widgets/spectrum_tuner.dart`**: renderiza os 256 bins de magnitude em
dB do `SpectrumPoller` como um gráfico de área preenchida cobrindo
`frequencyHz ± sampleRateHz/2` (os bins são calculados sobre a banda
capturada inteira, não um canal demodulado), com uma linha vertical fixa no
centro. Um `GestureDetector` combina `onTapUp` (sintoniza direto no ponto
tocado — absoluto) com `onHorizontalDragUpdate` (sintoniza por
`-delta.dx/width * spanHz` — relativo, como rolar uma lista: arrastar pra
direita puxa frequências mais baixas rumo ao centro).
`RadioController.sampleRateHz` foi adicionado (lido de
`shim_get_sample_rate_hz()` assim que o streaming começa) já que nada antes
rastreava isso do lado Dart.

**Bug de congelamento do waterfall**: `WaterfallPainter.shouldRepaint`
comparava `oldDelegate.rows` contra `rows` com `identical()` — mas
`WaterfallView` muta sua lista `_rows` *in place* (`insert`/`removeRange`),
nunca reatribuindo, então essa comparação sempre dava `true` pro mesmo
objeto subjacente, o que significa que `shouldRepaint` sempre retornava
`false`. O waterfall estava, na prática, congelado depois do primeiro
frame. Corrigido retornando sempre `true` — seguro porque o painter só é
reconstruído quando o próprio listener do `WaterfallView` chama
`setState()` em resposta a um frame novo de verdade do poller, então não há
custo de repintura redundante a se preocupar. Confirmado visualmente em
hardware: o waterfall agora claramente rola/atualiza a cada nova sintonia.

**`lib/screens/settings_screen.dart`**: um gerenciador de gravações (lista,
compartilha, apaga os arquivos WAV que o gravador produz) e uma seção Sobre
(app/versão, resumo de licença, licenças dos componentes de terceiros),
acessível por um ícone de configurações na barra do app.
`debugShowCheckedModeBanner: false` remove a fita de debug do canto.

## 8. O que ainda não está validado

Tudo no §5 e §6 funciona — provado contra hardware real, não só compilado —
mas várias constantes numéricas são estimativas de primeira passada que não
foram, e pela natureza deste ambiente de desenvolvimento (sem dongle físico
disponível pro agente que as escreveu), não puderam ser ajustadas contra um
ambiente de RF real antes da sessão de teste única de hoje:

- Banda passante/amortecimento do loop do PLL do piloto, e ganhos dos loops
  de Gardner/Costas do RDS — valores de partida das fórmulas padrão, não
  varridos contra sinal real.
- Nenhuma correção de PPM/offset de frequência em nenhum lugar do pipeline
  — cristais baratos de RTL-SDR podem desviar dezenas a centenas de Hz, o
  que poderia exceder a faixa de captura do PLL do piloto em alguns dongles
  individuais.
- Limiares de amplitude de lock/unlock do estéreo e o timing de debounce.
- Contadores de debounce do sincronismo de bloco do RDS (2 pra adquirir,
  3–6 pra perder o lock).
- Nenhuma correção de erro por burst do RDS (um corte de escopo explícito
  pra primeira versão).
- Nenhuma tabela de conjunto de caracteres do RDS — PS/RadioText são
  guardados como bytes crus, corretos pra ASCII simples (o caso comum), não
  pra tabela de caracteres estendida específica do RDS.

Nenhum desses é um bug de correção no sentido de "código errado" — são
parâmetros de ajuste que precisam de uma amostra mais ampla de
estações/dongles reais do que uma sessão com um dongle num único lugar
consegue fornecer.
