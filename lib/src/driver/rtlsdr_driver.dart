import 'package:driver_rtlsdr/driver_rtlsdr.dart' show DemodMode;
import 'package:flutter/foundation.dart';

/// One statistics snapshot from the native driver — decoupled from the raw
/// `ShimStats` FFI struct so callers (and fakes) never need `dart:ffi`.
@immutable
class RadioStats {
  const RadioStats({
    required this.iqBytesReceived,
    required this.ringOverflowCount,
    required this.rfLevelDbfs,
    required this.audioLevelDbfs,
    required this.squelchOpen,
    required this.recordingBytesWritten,
    required this.stereoLocked,
    required this.pilotLevel,
    required this.iqRecordingBytesWritten,
  });

  static const zero = RadioStats(
    iqBytesReceived: 0,
    ringOverflowCount: 0,
    rfLevelDbfs: -120,
    audioLevelDbfs: -90,
    squelchOpen: false,
    recordingBytesWritten: 0,
    stereoLocked: false,
    pilotLevel: 0,
    iqRecordingBytesWritten: 0,
  );

  final int iqBytesReceived;
  final int ringOverflowCount;
  final double rfLevelDbfs;
  final double audioLevelDbfs;
  final bool squelchOpen;
  final int recordingBytesWritten;
  final bool stereoLocked;
  final double pilotLevel;

  /// Bytes written by raw I/Q recording (see [RtlSdrDriver.startIqRecording])
  /// — independent of [recordingBytesWritten], which tracks the demodulated
  /// PCM recording. Both can be non-zero at once, since either recording can
  /// run on its own or together.
  final int iqRecordingBytesWritten;
}

/// One RDS snapshot (PI/PTY/TP/TA/PS/RadioText) — only meaningful when
/// [syncLocked] (WFM, stereo pilot locked, RDS enabled).
@immutable
class RdsInfo {
  const RdsInfo({
    required this.syncLocked,
    required this.piCode,
    required this.pty,
    required this.tp,
    required this.ta,
    required this.programService,
    required this.radioText,
    required this.generation,
  });

  static const empty = RdsInfo(
    syncLocked: false,
    piCode: 0,
    pty: 0,
    tp: false,
    ta: false,
    programService: '',
    radioText: '',
    generation: 0,
  );

  final bool syncLocked;
  final int piCode;
  final int pty;
  final bool tp;
  final bool ta;
  final String programService;
  final String radioText;
  final int generation;
}

/// Everything a radio session needs from the native RTL-SDR core — the seam
/// the rest of `core_rtlsdr` is built against, instead of every controller
/// calling `driver_rtlsdr`'s `NativeBindings` (raw FFI) directly.
///
/// [NativeRtlSdrDriver] is the real, Android-only implementation, a thin
/// adapter over `driver_rtlsdr`. Tests — here, and in consumers such as a
/// future `widget_rtlsdr` — should use `FakeRtlSdrDriver` from
/// `package:driver_rtlsdr/testing.dart` instead: FFI can't be exercised on a
/// host without an Android device, which is exactly why `driver_rtlsdr`
/// itself only unit-tests struct layout on the host and leaves everything
/// else to on-device integration tests. Depending on this interface instead
/// of the FFI bindings directly is what makes every controller in this
/// package unit-testable on any host, without a dongle or an emulator.
///
/// All setters return the native status code (`0` = success, matching
/// `rtlsdr_shim.h`) so callers can surface failures the same way the native
/// driver reports them.
abstract interface class RtlSdrDriver {
  /// Whether the native driver has an open device (set by the Kotlin side
  /// after the USB permission flow — see `UsbState`/`UsbChannel`).
  bool get isOpen;

  /// Closes the native device. Does not release this driver object itself —
  /// see [dispose].
  int close();

  int setFrequencyHz(int hz);
  int get frequencyHz;
  int setSampleRateHz(int hz);
  int get sampleRateHz;

  int startStreaming();
  int stopStreaming();
  bool get isStreaming;

  RadioStats getStats();

  // ---- Gain ------------------------------------------------------------
  // Tenths of a dB (librtlsdr's own convention), e.g. 40 = 4.0 dB.

  int setGainMode({required bool auto});
  int setGainTenthDb(int tenthDb);

  /// Gains supported by the tuner, in tenths of a dB. Needs the device
  /// already open — call once after `deviceReady`.
  List<int> getGainList();

  // ---- Demodulation / squelch --------------------------------------------
  // Switching modes only takes effect on the next startStreaming().

  int setDemodMode(DemodMode mode);
  DemodMode get demodMode;
  int setSquelchThresholdDb(double thresholdDb);

  // ---- Stereo (WFM) ------------------------------------------------------
  // Applied live, no need to stop/restart streaming.

  int setStereoEnabled(bool enabled);

  // ---- RDS -----------------------------------------------------------------

  int setRdsEnabled(bool enabled);
  RdsInfo getRdsInfo();

  // ---- Spectrum --------------------------------------------------------------
  // Snapshot of the whole captured band (not the demodulated channel), ready
  // to plot directly — bin 0 = lower edge, bin[n-1] = upper edge.

  List<double> getSpectrumDb(int numBins);

  // ---- Recording -----------------------------------------------------------
  // Records the same PCM that already goes to the speaker, directly to a WAV.

  int startRecording(String filePath);
  int stopRecording();
  bool get isRecording;

  /// Same as [startRecording], but writes through an already-open file
  /// descriptor instead of a path — for destinations with no plain
  /// filesystem path available, e.g. Android's public Downloads folder via
  /// MediaStore (see `core_rtlsdr`'s
  /// `RecordingController.startRecordingToDownloads`).
  int startRecordingFd(int fd);

  // ---- Raw I/Q recording -------------------------------------------------
  // Dumps the interleaved 8-bit unsigned I/Q exactly as the dongle sends it
  // (the ".cu8" convention used by rtl_sdr/GNU Radio/gqrx), tapped before
  // decimation/demodulation — independent of [startRecording]/[stopRecording]
  // above, both can run at once.

  int startIqRecording(String filePath);
  int stopIqRecording();
  bool get isIqRecording;

  /// Same as [startIqRecording], but writes through an already-open file
  /// descriptor instead of a path — see [startRecordingFd].
  int startIqRecordingFd(int fd);

  /// Releases native resources held by this driver instance (FFI struct
  /// buffers). Does NOT close the device (see [close]) — call this once,
  /// when you're done with the driver object itself (app shutdown, or
  /// swapping implementations).
  void dispose();
}
