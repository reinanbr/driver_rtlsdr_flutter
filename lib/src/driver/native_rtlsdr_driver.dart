import 'dart:ffi' as ffi;

import 'package:driver_rtlsdr/driver_rtlsdr.dart' as driver;
import 'package:ffi/ffi.dart' as pkg_ffi;

import 'rtlsdr_driver.dart';

/// [RtlSdrDriver] backed by the real native core — `driver_rtlsdr`'s
/// `NativeBindings`, FFI into `libnative_rtlsdr.so`. Only usable on Android,
/// and only after the USB permission flow has produced a `deviceReady`
/// event (see `UsbState`/`UsbChannel`, re-exported from `core_rtlsdr.dart`).
///
/// Purely an adapter: converts the raw FFI structs (`ShimStats`,
/// `ShimRdsInfo`) to the plain [RadioStats]/[RdsInfo] models and manages the
/// native buffers those calls need. No policy lives here — that's the
/// controllers' job.
class NativeRtlSdrDriver implements RtlSdrDriver {
  final ffi.Pointer<driver.ShimStats> _statsPtr = pkg_ffi
      .calloc<driver.ShimStats>();
  final ffi.Pointer<driver.ShimRdsInfo> _rdsPtr = pkg_ffi
      .calloc<driver.ShimRdsInfo>();
  bool _disposed = false;

  @override
  bool get isOpen => driver.NativeBindings.shimIsOpen() != 0;

  @override
  int close() => driver.NativeBindings.shimClose();

  @override
  int setFrequencyHz(int hz) => driver.NativeBindings.shimSetFrequencyHz(hz);

  @override
  int get frequencyHz => driver.NativeBindings.shimGetFrequencyHz();

  @override
  int setSampleRateHz(int hz) => driver.NativeBindings.shimSetSampleRateHz(hz);

  @override
  int get sampleRateHz => driver.NativeBindings.shimGetSampleRateHz();

  @override
  int startStreaming() => driver.NativeBindings.shimStartStreaming();

  @override
  int stopStreaming() => driver.NativeBindings.shimStopStreaming();

  @override
  bool get isStreaming => driver.NativeBindings.shimIsStreaming() != 0;

  @override
  RadioStats getStats() {
    _assertNotDisposed();
    final status = driver.NativeBindings.shimGetStats(_statsPtr);
    if (status != 0) return RadioStats.zero;
    final s = _statsPtr.ref;
    return RadioStats(
      iqBytesReceived: s.iqBytesReceived,
      ringOverflowCount: s.ringOverflowCount,
      rfLevelDbfs: s.rfLevelDbfs,
      audioLevelDbfs: s.audioLevelDbfs,
      squelchOpen: s.squelchOpen != 0,
      recordingBytesWritten: s.recordingBytesWritten,
      stereoLocked: s.stereoLocked != 0,
      pilotLevel: s.pilotLevel,
      iqRecordingBytesWritten: s.iqRecordingBytesWritten,
    );
  }

  @override
  int setGainMode({required bool auto}) =>
      driver.NativeBindings.shimSetGainMode(auto ? 1 : 0);

  @override
  int setGainTenthDb(int tenthDb) =>
      driver.NativeBindings.shimSetGainTenthDb(tenthDb);

  @override
  List<int> getGainList() {
    const maxCount = 64;
    final buffer = pkg_ffi.calloc<ffi.Int32>(maxCount);
    try {
      final count = driver.NativeBindings.shimGetGainList(buffer, maxCount);
      if (count <= 0) return const [];
      return List<int>.generate(count, (i) => buffer[i]);
    } finally {
      pkg_ffi.calloc.free(buffer);
    }
  }

  @override
  int setDemodMode(driver.DemodMode mode) =>
      driver.NativeBindings.shimSetDemodMode(mode.nativeValue);

  @override
  driver.DemodMode get demodMode => driver.DemodMode.fromNativeValue(
    driver.NativeBindings.shimGetDemodMode(),
  );

  @override
  int setSquelchThresholdDb(double thresholdDb) =>
      driver.NativeBindings.shimSetSquelchThresholdDb(thresholdDb);

  @override
  int setStereoEnabled(bool enabled) =>
      driver.NativeBindings.shimSetStereoEnabled(enabled ? 1 : 0);

  @override
  int setRdsEnabled(bool enabled) =>
      driver.NativeBindings.shimSetRdsEnabled(enabled ? 1 : 0);

  @override
  RdsInfo getRdsInfo() {
    _assertNotDisposed();
    final status = driver.NativeBindings.shimGetRdsInfo(_rdsPtr);
    if (status != 0) return RdsInfo.empty;
    final info = _rdsPtr.ref;
    return RdsInfo(
      syncLocked: info.syncLocked != 0,
      piCode: info.piCode,
      pty: info.pty,
      tp: info.tp != 0,
      ta: info.ta != 0,
      programService: _decodeFixedString(info.ps, 8),
      radioText: _decodeFixedString(info.radiotext, 64),
      generation: info.generation,
    );
  }

  @override
  List<double> getSpectrumDb(int numBins) {
    final buffer = pkg_ffi.calloc<ffi.Float>(numBins);
    try {
      final count = driver.NativeBindings.shimGetSpectrumDb(buffer, numBins);
      if (count <= 0) return const [];
      return List<double>.generate(count, (i) => buffer[i]);
    } finally {
      pkg_ffi.calloc.free(buffer);
    }
  }

  @override
  int startRecording(String filePath) {
    final pathPtr = filePath.toNativeUtf8();
    try {
      return driver.NativeBindings.shimStartRecording(pathPtr);
    } finally {
      pkg_ffi.calloc.free(pathPtr);
    }
  }

  @override
  int startRecordingFd(int fd) =>
      driver.NativeBindings.shimStartRecordingFd(fd);

  @override
  int stopRecording() => driver.NativeBindings.shimStopRecording();

  @override
  bool get isRecording => driver.NativeBindings.shimIsRecording() != 0;

  @override
  int startIqRecording(String filePath) {
    final pathPtr = filePath.toNativeUtf8();
    try {
      return driver.NativeBindings.shimStartIqRecording(pathPtr);
    } finally {
      pkg_ffi.calloc.free(pathPtr);
    }
  }

  @override
  int startIqRecordingFd(int fd) =>
      driver.NativeBindings.shimStartIqRecordingFd(fd);

  @override
  int stopIqRecording() => driver.NativeBindings.shimStopIqRecording();

  @override
  bool get isIqRecording => driver.NativeBindings.shimIsIqRecording() != 0;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    pkg_ffi.calloc.free(_statsPtr);
    pkg_ffi.calloc.free(_rdsPtr);
  }

  void _assertNotDisposed() {
    if (_disposed) {
      throw StateError('NativeRtlSdrDriver used after dispose()');
    }
  }

  String _decodeFixedString(ffi.Array<ffi.Uint8> array, int length) {
    final bytes = List<int>.generate(length, (i) => array[i]);
    final nulIndex = bytes.indexOf(0);
    final effectiveLength = nulIndex >= 0 ? nulIndex : length;
    return String.fromCharCodes(bytes.sublist(0, effectiveLength)).trimRight();
  }
}
