/// Driver Android para dongles RTL-SDR (RTL2832U) via USB-OTG.
///
/// Extraído do app `rtl-sdr mobile` (pasta irmã deste pacote) como um
/// plugin Flutter reutilizável — o núcleo nativo (C, GPLv2, ver
/// `android/src/main/cpp/`) não muda entre este pacote e o app original; o
/// que muda é que aqui ele é exposto como uma API pública pra qualquer app
/// Flutter de rádio definido por software construir sua própria UI em
/// cima, em vez de vir embutido dentro de um app específico.
///
/// ## O que este pacote NÃO faz
///
/// De propósito, pra manter o driver focado: não tem UI, não gerencia um
/// foreground service (mantendo o processo vivo com o app em segundo plano
/// durante streaming — isso é decisão de UX de cada app consumidor), e não
/// decide onde salvar gravações (`shim_start_recording` recebe um caminho
/// absoluto — o app escolhe onde, tipicamente via `path_provider`).
///
/// ## Como montar um app em cima
///
/// 1. [UsbState] + [UsbChannel]: detecta o dongle, pede permissão, escuta o
///    evento `deviceReady` (só então o driver nativo está aberto e pronto).
/// 2. [NativeBindings]: sintonia (`shimSetFrequencyHz`), modo de demodulação
///    ([DemodMode] — WFM/NFM/AM), ganho, squelch, estéreo, RDS, streaming
///    (`shimStartStreaming`/`shimStopStreaming`), estatísticas ([ShimStats],
///    via `shimGetStats`), RDS ([ShimRdsInfo], via `shimGetRdsInfo`),
///    espectro (`shimGetSpectrumDb`) e gravação (`shimStartRecording`).
/// 3. O app monta seus próprios controllers (`ChangeNotifier` + polling
///    periódico é o padrão usado no app de referência) por cima dessas
///    chamadas — ver `example/` neste pacote para uma implementação mínima
///    funcional, e o app `rtl-sdr mobile` (irmão deste pacote) para uma
///    implementação completa (estéreo, RDS, scan automático, gravação,
///    sintonizador visual por espectro).
///
/// Ver README.md pra detalhes de integração (manifest, permissões) e
/// `docs/` no app `rtl-sdr mobile` pra como o driver nativo em si foi
/// projetado (PLL do piloto estéreo, decodificador RDS, etc).
library;

export 'src/demod_mode.dart';
export 'src/native_bindings.dart';
export 'src/native_library.dart';
export 'src/shim_types.dart';
export 'src/usb_channel.dart';
export 'src/usb_state.dart';
