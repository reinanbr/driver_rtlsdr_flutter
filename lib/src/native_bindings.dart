import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart' as pkg_ffi;

import 'native_library.dart';
import 'shim_types.dart';

/// Hand-written bindings (not ffigen) for `rtlsdr_shim.h`'s public API —
/// small and stable enough that ffigen's extra complexity isn't worth it.
/// `shim_open_with_fd` deliberately has NO binding here: only Kotlin (via
/// JNI, `DriverRtlsdrPlugin.kt`) has a valid USB file descriptor to pass —
/// see [UsbChannel]/[UsbState] for the permission flow.
class NativeBindings {
  NativeBindings._();

  static final ffi.DynamicLibrary _lib = NativeLibrary.instance;

  static final int Function() shimIsOpen = _lib
      .lookupFunction<ffi.Int32 Function(), int Function()>('shim_is_open');

  static final int Function() shimClose = _lib
      .lookupFunction<ffi.Int32 Function(), int Function()>('shim_close');

  static final int Function(int freqHz) shimSetFrequencyHz = _lib
      .lookupFunction<ffi.Int32 Function(ffi.Uint32), int Function(int)>(
        'shim_set_frequency_hz',
      );

  static final int Function() shimGetFrequencyHz = _lib
      .lookupFunction<ffi.Uint32 Function(), int Function()>(
        'shim_get_frequency_hz',
      );

  static final int Function(int rateHz) shimSetSampleRateHz = _lib
      .lookupFunction<ffi.Int32 Function(ffi.Uint32), int Function(int)>(
        'shim_set_sample_rate_hz',
      );

  static final int Function() shimGetSampleRateHz = _lib
      .lookupFunction<ffi.Uint32 Function(), int Function()>(
        'shim_get_sample_rate_hz',
      );

  static final int Function() shimStartStreaming = _lib
      .lookupFunction<ffi.Int32 Function(), int Function()>(
        'shim_start_streaming',
      );

  static final int Function() shimStopStreaming = _lib
      .lookupFunction<ffi.Int32 Function(), int Function()>(
        'shim_stop_streaming',
      );

  static final int Function() shimIsStreaming = _lib
      .lookupFunction<ffi.Int32 Function(), int Function()>(
        'shim_is_streaming',
      );

  static final int Function(ffi.Pointer<ShimStats> out) shimGetStats = _lib
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ShimStats>),
        int Function(ffi.Pointer<ShimStats>)
      >('shim_get_stats');

  // ---- Gain ----------------------------------------------------------------
  // Tenths of a dB (librtlsdr's own convention), e.g. 40 = 4.0 dB.

  static final int Function(int autoGain) shimSetGainMode = _lib
      .lookupFunction<ffi.Int32 Function(ffi.Int32), int Function(int)>(
        'shim_set_gain_mode',
      );

  static final int Function(int gainTenthsDb) shimSetGainTenthDb = _lib
      .lookupFunction<ffi.Int32 Function(ffi.Int32), int Function(int)>(
        'shim_set_gain_tenth_db',
      );

  static final int Function(ffi.Pointer<ffi.Int32> out, int maxCount)
  shimGetGainList = _lib
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Int32>, ffi.Int32),
        int Function(ffi.Pointer<ffi.Int32>, int)
      >('shim_get_gain_list');

  // ---- Demodulation / squelch ----------------------------------------------
  // Switching modes only takes effect on the next shim_start_streaming().

  static final int Function(int mode) shimSetDemodMode = _lib
      .lookupFunction<ffi.Int32 Function(ffi.Int32), int Function(int)>(
        'shim_set_demod_mode',
      );

  static final int Function() shimGetDemodMode = _lib
      .lookupFunction<ffi.Int32 Function(), int Function()>(
        'shim_get_demod_mode',
      );

  static final int Function(double thresholdDb) shimSetSquelchThresholdDb = _lib
      .lookupFunction<ffi.Int32 Function(ffi.Float), int Function(double)>(
        'shim_set_squelch_threshold_db',
      );

  // ---- Stereo (WFM) --------------------------------------------------------
  // Applied live, no need to stop/restart streaming.

  static final int Function(int enabled) shimSetStereoEnabled = _lib
      .lookupFunction<ffi.Int32 Function(ffi.Int32), int Function(int)>(
        'shim_set_stereo_enabled',
      );

  // ---- RDS -------------------------------------------------------------------

  static final int Function(int enabled) shimSetRdsEnabled = _lib
      .lookupFunction<ffi.Int32 Function(ffi.Int32), int Function(int)>(
        'shim_set_rds_enabled',
      );

  static final int Function(ffi.Pointer<ShimRdsInfo> out) shimGetRdsInfo = _lib
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ShimRdsInfo>),
        int Function(ffi.Pointer<ShimRdsInfo>)
      >('shim_get_rds_info');

  // ---- Spectrum --------------------------------------------------------------
  // Snapshot of the whole captured band (not the demodulated channel),
  // ready to plot directly — bin 0 = lower edge, bin[n-1] = upper edge.

  static final int Function(ffi.Pointer<ffi.Float> out, int numBins)
  shimGetSpectrumDb = _lib
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<ffi.Float>, ffi.Int32),
        int Function(ffi.Pointer<ffi.Float>, int)
      >('shim_get_spectrum_db');

  // ---- Recording ---------------------------------------------------------------
  // Records the same PCM that already goes to the speaker, directly to a WAV.

  static final int Function(ffi.Pointer<pkg_ffi.Utf8> filePath)
  shimStartRecording = _lib
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<pkg_ffi.Utf8>),
        int Function(ffi.Pointer<pkg_ffi.Utf8>)
      >('shim_start_recording');

  static final int Function() shimStopRecording = _lib
      .lookupFunction<ffi.Int32 Function(), int Function()>(
        'shim_stop_recording',
      );

  static final int Function() shimIsRecording = _lib
      .lookupFunction<ffi.Int32 Function(), int Function()>(
        'shim_is_recording',
      );

  // ---- Raw I/Q recording ---------------------------------------------------
  // Dumps the interleaved 8-bit unsigned I/Q exactly as the dongle sends it
  // (rtl_sdr/GNU Radio/gqrx ".cu8" convention), before decimation/demod —
  // independent of shimStartRecording, both can run at once.

  static final int Function(ffi.Pointer<pkg_ffi.Utf8> filePath)
  shimStartIqRecording = _lib
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<pkg_ffi.Utf8>),
        int Function(ffi.Pointer<pkg_ffi.Utf8>)
      >('shim_start_iq_recording');

  static final int Function() shimStopIqRecording = _lib
      .lookupFunction<ffi.Int32 Function(), int Function()>(
        'shim_stop_iq_recording',
      );

  static final int Function() shimIsIqRecording = _lib
      .lookupFunction<ffi.Int32 Function(), int Function()>(
        'shim_is_iq_recording',
      );
}
