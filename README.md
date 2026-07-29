# driver_rtlsdr

Driver Android (Flutter plugin) para dongles RTL-SDR (chipset RTL2832U) via
USB-OTG. Extraído do app [`rtl-sdr mobile`](../rtl-sdr%20mobile) (pasta irmã
deste pacote) pra que outros apps Flutter de rádio definido por software
possam construir sua própria UI/UX em cima do mesmo núcleo nativo, em vez de
reimplementar USB + libusb + librtlsdr + DSP do zero.

O núcleo nativo (C, `android/src/main/cpp/`) é **idêntico** ao do app de
origem — mesmo pipeline: permissão/abertura USB → streaming de IQ bruto →
decimação em dois estágios → demodulação (WFM/NFM/AM, com estéreo e RDS em
WFM) → PCM pro alto-falante (Oboe), com gravação em WAV e leitura de
espectro pra waterfall/visualização.

## O que este pacote fornece

- **USB**: detecção do dongle, fluxo de permissão (`UsbState`/`UsbChannel`,
  `MethodChannel`/`EventChannel` sobre `DriverRtlsdrPlugin.kt`).
- **Sintonia**: frequência, taxa de amostragem.
- **Demodulação**: WFM (com estéreo e RDS), NFM, AM (`DemodMode`).
- **Estéreo WFM**: PLL de piloto de 19kHz, liga/desliga ao vivo
  (`shimSetStereoEnabled`), lock reportado em `ShimStats.stereoLocked`.
- **RDS**: PI/PTY/TP/TA/PS/RadioText (`ShimRdsInfo`, via `shimGetRdsInfo`),
  liga/desliga ao vivo (`shimSetRdsEnabled`).
- **Ganho**: automático (AGC) ou manual, lista de ganhos suportados pelo
  tuner.
- **Squelch**: NFM/AM (WFM não usa — rádio comercial não teria squelch).
- **Espectro**: snapshot em dB da banda inteira capturada, pronto pra
  plotar (`shimGetSpectrumDb`).
- **Gravação**: grava o PCM demodulado (mono ou estéreo, o que a sessão
  estiver produzindo) direto num WAV (`shimStartRecording`/
  `shimStopRecording`).
- **Estatísticas**: taxa de IQ, overflow de ring buffer, nível de RF/áudio
  (`ShimStats`, via `shimGetStats`).

## O que este pacote deliberadamente NÃO fornece

- **UI**: zero widgets. O app consumidor monta a interface.
- **Foreground service**: manter o processo vivo em segundo plano durante
  streaming é decisão de UX de cada app — não vem embutido aqui. Um app
  consumidor que precise disso pode implementar seu próprio (ver
  `StreamingService.kt` no app `rtl-sdr mobile` como referência).
- **Onde salvar gravações**: `shimStartRecording` recebe um caminho
  absoluto — o app escolhe (tipicamente via `path_provider`).
- **Presets, scan automático, carrossel/sintonizador visual**: são lógica de
  aplicação construída em cima da API deste driver, não parte dele. O app
  `rtl-sdr mobile` tem implementações de referência de tudo isso
  (`lib/radio/scan_controller.dart`, `lib/widgets/spectrum_tuner.dart`,
  etc.) que podem ser adaptadas.

## Instalação

```yaml
dependencies:
  driver_rtlsdr:
    path: ../driver_rtlsdr # ou uma referência git/pub, se publicado
```

## Integrando num app novo

1. **`AndroidManifest.xml`** do seu app — adicione o intent-filter de
   auto-abertura ao plugar o dongle (opcional, mas é o que faz o Android
   oferecer abrir seu app quando o usuário conecta o dongle) e aponte o
   `meta-data` pro filtro de VID/PID já incluído neste pacote:

   ```xml
   <activity ...>
       <intent-filter>
           <action android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED" />
       </intent-filter>
       <meta-data
           android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED"
           android:resource="@xml/device_filter" />
   </activity>
   ```

   `@xml/device_filter` resolve pro recurso do próprio `driver_rtlsdr`
   (mesclado no build pelo merger de recursos do Gradle — não precisa
   copiar nada). `android.hardware.usb.host` já é declarado pelo manifest
   do plugin e também é mesclado automaticamente.

2. **`minSdk = 26`** — exigido pelo caminho de baixa latência do
   Oboe/AAudio usado internamente pra saída de áudio.

3. **Ciclo de vida**: `UsbState` + `UsbChannel` (chame
   `refreshConnectedDevices()` ao iniciar sua tela — pega o caso do dongle
   já estar plugado quando o app abre) → `requestPermission()` → escute o
   evento `deviceReady` → a partir daí, `NativeBindings.shim*` estão livres
   pra usar (`shimSetFrequencyHz`, `shimSetDemodMode`,
   `shimStartStreaming`, etc.).

4. Ver `example/` neste pacote pra uma implementação mínima e funcional
   completa (permissão → sintonia por slider → seleção de modo →
   start/stop streaming → estatísticas ao vivo, incluindo lock do piloto
   estéreo).

## Testes

- `test/` — testes de unidade Dart puros, rodam no host (sem Android nem
  dongle): `DemodMode` (valores nativos, round-trip, squelch) e o
  **tamanho em bytes dos structs FFI** (`ShimStats`/`ShimRdsInfo`) contra o
  layout esperado calculado a partir de `rtlsdr_shim.h` — pega o erro mais
  comum ao evoluir a API nativa (esquecer de espelhar um campo novo dos
  dois lados). Rodar: `flutter test`.
- `example/integration_test/` — roda num device/emulador Android de
  verdade; confirma que `libnative_rtlsdr.so` compila, linka e carrega
  nesse ABI específico, e que uma chamada FFI real funciona — sem precisar
  de um dongle fisicamente conectado. Rodar:
  `cd example && flutter test integration_test`.
- **Validação contra hardware real**: o núcleo nativo deste pacote é
  byte-a-byte o mesmo do app `rtl-sdr mobile`, que foi testado ao vivo
  contra um dongle RTL2838U real (permissão USB, sintonia, streaming,
  troca de modo, lock do piloto estéreo, sincronismo e decodificação de
  RDS contra uma estação real, gravação, scan) — ver
  `../rtl-sdr mobile/docs/how-it-was-built.md` pros resultados completos
  dessa validação. O **app de exemplo deste pacote especificamente** teve
  o build nativo validado (compilou e linkou limpo do zero, todas as
  fontes vendorizadas/adaptadas corretamente) e foi instalado com sucesso
  num device real; o smoke test visual ao vivo (abrir a tela, pedir
  permissão, sintonizar) ficou pendente porque o aparelho de teste ficou
  sem bateria (5%) no meio da sessão — não uma falha do app. Fica como
  primeiro passo de validação recomendado antes de publicar/depender deste
  pacote em produção.

## Licença

GPLv2, ou (a seu critério) qualquer versão posterior — ver
[`LICENSE`](LICENSE). Este driver vincula `librtlsdr` (GPLv2-or-later), o
que exige que qualquer app que o use seja distribuído sob GPL. `libusb`
(LGPL-2.1) e KissFFT (BSD-3-Clause) são vendorizados em
`android/src/main/cpp/vendor/`; Oboe (Apache-2.0) é dependência via
Gradle/Prefab. Ver `LICENSE` para o detalhamento completo.

## Arquitetura / como o driver nativo funciona

Ver [`../rtl-sdr mobile/docs/how-it-was-built.md`](../rtl-sdr%20mobile/docs/how-it-was-built.md)
(e a tradução [`como-foi-construido.md`](../rtl-sdr%20mobile/docs/como-foi-construido.md))
pra uma explicação técnica detalhada de como a decodificação estéreo/RDS, o
scan automático, a gravação e o sintonizador visual foram projetados e
validados — esse documento descreve o mesmo núcleo nativo que este pacote
expõe como plugin.
