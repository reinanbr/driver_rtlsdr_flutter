import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart' as pkg_ffi;

import 'native_library.dart';
import 'shim_types.dart';

/// Bindings escritas à mão (não ffigen) para a API pública de `rtlsdr_shim.h`
/// — pequena e estável o bastante para não valer a complexidade extra do
/// ffigen. `shim_open_with_fd` propositalmente NÃO tem binding aqui: só o
/// Kotlin (via JNI, `DriverRtlsdrPlugin.kt`) tem um file descriptor USB
/// válido pra passar — ver [UsbChannel]/[UsbState] pro fluxo de permissão.
class NativeBindings {
  NativeBindings._();

  static final ffi.DynamicLibrary _lib = NativeLibrary.instance;

  static final int Function() shimIsOpen =
      _lib.lookupFunction<ffi.Int32 Function(), int Function()>('shim_is_open');

  static final int Function() shimClose =
      _lib.lookupFunction<ffi.Int32 Function(), int Function()>('shim_close');

  static final int Function(int freqHz) shimSetFrequencyHz = _lib
      .lookupFunction<ffi.Int32 Function(ffi.Uint32), int Function(int)>('shim_set_frequency_hz');

  static final int Function() shimGetFrequencyHz =
      _lib.lookupFunction<ffi.Uint32 Function(), int Function()>('shim_get_frequency_hz');

  static final int Function(int rateHz) shimSetSampleRateHz = _lib
      .lookupFunction<ffi.Int32 Function(ffi.Uint32), int Function(int)>('shim_set_sample_rate_hz');

  static final int Function() shimGetSampleRateHz =
      _lib.lookupFunction<ffi.Uint32 Function(), int Function()>('shim_get_sample_rate_hz');

  static final int Function() shimStartStreaming =
      _lib.lookupFunction<ffi.Int32 Function(), int Function()>('shim_start_streaming');

  static final int Function() shimStopStreaming =
      _lib.lookupFunction<ffi.Int32 Function(), int Function()>('shim_stop_streaming');

  static final int Function() shimIsStreaming =
      _lib.lookupFunction<ffi.Int32 Function(), int Function()>('shim_is_streaming');

  static final int Function(ffi.Pointer<ShimStats> out) shimGetStats = _lib.lookupFunction<
      ffi.Int32 Function(ffi.Pointer<ShimStats>),
      int Function(ffi.Pointer<ShimStats>)>('shim_get_stats');

  // ---- Ganho -------------------------------------------------------------
  // Décimos de dB (convenção da própria librtlsdr), ex. 40 = 4.0 dB.

  static final int Function(int autoGain) shimSetGainMode = _lib
      .lookupFunction<ffi.Int32 Function(ffi.Int32), int Function(int)>('shim_set_gain_mode');

  static final int Function(int gainTenthsDb) shimSetGainTenthDb = _lib
      .lookupFunction<ffi.Int32 Function(ffi.Int32), int Function(int)>('shim_set_gain_tenth_db');

  static final int Function(ffi.Pointer<ffi.Int32> out, int maxCount) shimGetGainList = _lib.lookupFunction<
      ffi.Int32 Function(ffi.Pointer<ffi.Int32>, ffi.Int32),
      int Function(ffi.Pointer<ffi.Int32>, int)>('shim_get_gain_list');

  // ---- Demodulação / squelch ----------------------------------------------
  // Trocar o modo só tem efeito no próximo shim_start_streaming().

  static final int Function(int mode) shimSetDemodMode = _lib
      .lookupFunction<ffi.Int32 Function(ffi.Int32), int Function(int)>('shim_set_demod_mode');

  static final int Function() shimGetDemodMode =
      _lib.lookupFunction<ffi.Int32 Function(), int Function()>('shim_get_demod_mode');

  static final int Function(double thresholdDb) shimSetSquelchThresholdDb = _lib
      .lookupFunction<ffi.Int32 Function(ffi.Float), int Function(double)>('shim_set_squelch_threshold_db');

  // ---- Estéreo (WFM) --------------------------------------------------------
  // Aplicado ao vivo, sem precisar parar/reiniciar o streaming.

  static final int Function(int enabled) shimSetStereoEnabled = _lib
      .lookupFunction<ffi.Int32 Function(ffi.Int32), int Function(int)>('shim_set_stereo_enabled');

  // ---- RDS -------------------------------------------------------------------

  static final int Function(int enabled) shimSetRdsEnabled = _lib
      .lookupFunction<ffi.Int32 Function(ffi.Int32), int Function(int)>('shim_set_rds_enabled');

  static final int Function(ffi.Pointer<ShimRdsInfo> out) shimGetRdsInfo = _lib.lookupFunction<
      ffi.Int32 Function(ffi.Pointer<ShimRdsInfo>),
      int Function(ffi.Pointer<ShimRdsInfo>)>('shim_get_rds_info');

  // ---- Espectro ------------------------------------------------------------
  // Snapshot da banda inteira capturada (não o canal demodulado), pronto
  // pra plotar direto — bin 0 = borda inferior, bin[n-1] = borda superior.

  static final int Function(ffi.Pointer<ffi.Float> out, int numBins) shimGetSpectrumDb = _lib.lookupFunction<
      ffi.Int32 Function(ffi.Pointer<ffi.Float>, ffi.Int32),
      int Function(ffi.Pointer<ffi.Float>, int)>('shim_get_spectrum_db');

  // ---- Gravação --------------------------------------------------------------
  // Grava o mesmo PCM que já vai pro alto-falante, direto num WAV.

  static final int Function(ffi.Pointer<pkg_ffi.Utf8> filePath) shimStartRecording = _lib.lookupFunction<
      ffi.Int32 Function(ffi.Pointer<pkg_ffi.Utf8>),
      int Function(ffi.Pointer<pkg_ffi.Utf8>)>('shim_start_recording');

  static final int Function() shimStopRecording =
      _lib.lookupFunction<ffi.Int32 Function(), int Function()>('shim_stop_recording');

  static final int Function() shimIsRecording =
      _lib.lookupFunction<ffi.Int32 Function(), int Function()>('shim_is_recording');
}
