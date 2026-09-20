import 'package:driver_rtlsdr/driver_rtlsdr.dart' show DemodMode;

import 'rtlsdr_driver.dart';

/// In-memory [RtlSdrDriver] with no FFI/Android dependency — for unit tests
/// of `core_rtlsdr` controllers, and for consumers (e.g. a future
/// `widget_rtlsdr`) that want to test UI against a radio session without a
/// dongle or an emulator.
///
/// State is exposed as plain mutable fields so a test can poke "hardware"
/// behavior directly (e.g. `fake.rfLevelDbfs = -10;`) and then assert how a
/// controller reacted to it.
class FakeRtlSdrDriver implements RtlSdrDriver {
  FakeRtlSdrDriver({this.signalLevelForFrequency});

  /// Optional: makes [getStats]' `rfLevelDbfs` a function of the currently
  /// tuned frequency instead of the static [rfLevelDbfs] field — handy for
  /// testing `ScanController`, which tunes across a range and samples the
  /// level at each step.
  final double Function(int frequencyHz)? signalLevelForFrequency;

  /// Set to `true` to make the next mutating call fail (return a non-zero
  /// status), then automatically reset to `false` — for testing error
  /// handling paths (`lastError`, etc.) without needing real hardware to
  /// misbehave.
  bool failNextCall = false;

  bool open = true;
  bool _streaming = false;
  bool _recording = false;
  String? recordingPath;
  int? recordingFd;
  bool _iqRecording = false;
  String? iqRecordingPath;
  int? iqRecordingFd;

  int _frequencyHz = 100000000; // 100.0 MHz
  int _sampleRateHz = 1024000;
  DemodMode _demodMode = DemodMode.wfm;
  bool _gainAuto = true;
  int _gainTenthDb = 0;
  double _squelchThresholdDb = -40.0;
  bool _stereoEnabled = true;
  bool _rdsEnabled = true;

  /// Gains a real RTL2832U + R820T2 tuner reports, in tenths of a dB —
  /// realistic defaults so `getGainList()` behaves like real hardware
  /// without a test having to set it up.
  List<int> gainList = const [
    0,
    9,
    14,
    27,
    37,
    77,
    87,
    125,
    144,
    157,
    166,
    197,
    207,
    229,
    254,
    280,
    297,
    328,
    338,
    364,
    372,
    386,
    402,
    421,
    434,
    439,
    445,
    480,
    496,
  ];

  double rfLevelDbfs = -120.0;
  double audioLevelDbfs = -90.0;
  bool squelchOpen = true;
  bool stereoLocked = false;
  double pilotLevel = 0.0;
  int iqBytesReceived = 0;
  int ringOverflowCount = 0;
  int recordingBytesWritten = 0;
  int iqRecordingBytesWritten = 0;
  RdsInfo rdsInfo = RdsInfo.empty;
  List<double> spectrumDb = List<double>.filled(256, -120.0);

  @override
  bool get isOpen => open;

  @override
  int close() {
    final status = _consumeStatus();
    if (status == 0) open = false;
    return status;
  }

  @override
  int setFrequencyHz(int hz) {
    final status = _consumeStatus();
    if (status == 0) _frequencyHz = hz;
    return status;
  }

  @override
  int get frequencyHz => _frequencyHz;

  @override
  int setSampleRateHz(int hz) {
    final status = _consumeStatus();
    if (status == 0) _sampleRateHz = hz;
    return status;
  }

  @override
  int get sampleRateHz => _sampleRateHz;

  @override
  int startStreaming() {
    final status = _consumeStatus();
    if (status == 0) _streaming = true;
    return status;
  }

  @override
  int stopStreaming() {
    final status = _consumeStatus();
    if (status == 0) _streaming = false;
    return status;
  }

  @override
  bool get isStreaming => _streaming;

  @override
  RadioStats getStats() {
    final level = signalLevelForFrequency?.call(_frequencyHz) ?? rfLevelDbfs;
    return RadioStats(
      iqBytesReceived: iqBytesReceived,
      ringOverflowCount: ringOverflowCount,
      rfLevelDbfs: level,
      audioLevelDbfs: audioLevelDbfs,
      squelchOpen: squelchOpen,
      recordingBytesWritten: recordingBytesWritten,
      stereoLocked: stereoLocked,
      pilotLevel: pilotLevel,
      iqRecordingBytesWritten: iqRecordingBytesWritten,
    );
  }

  @override
  int setGainMode({required bool auto}) {
    final status = _consumeStatus();
    if (status == 0) _gainAuto = auto;
    return status;
  }

  @override
  int setGainTenthDb(int tenthDb) {
    final status = _consumeStatus();
    if (status == 0) {
      _gainTenthDb = tenthDb;
      _gainAuto = false;
    }
    return status;
  }

  bool get gainAuto => _gainAuto;
  int get gainTenthDb => _gainTenthDb;

  @override
  List<int> getGainList() => List.unmodifiable(gainList);

  @override
  int setDemodMode(DemodMode mode) {
    final status = _consumeStatus();
    if (status == 0) _demodMode = mode;
    return status;
  }

  @override
  DemodMode get demodMode => _demodMode;

  @override
  int setSquelchThresholdDb(double thresholdDb) {
    final status = _consumeStatus();
    if (status == 0) _squelchThresholdDb = thresholdDb;
    return status;
  }

  double get squelchThresholdDb => _squelchThresholdDb;

  @override
  int setStereoEnabled(bool enabled) {
    final status = _consumeStatus();
    if (status == 0) _stereoEnabled = enabled;
    return status;
  }

  bool get stereoEnabled => _stereoEnabled;

  @override
  int setRdsEnabled(bool enabled) {
    final status = _consumeStatus();
    if (status == 0) _rdsEnabled = enabled;
    return status;
  }

  bool get rdsEnabled => _rdsEnabled;

  @override
  RdsInfo getRdsInfo() => rdsInfo;

  @override
  List<double> getSpectrumDb(int numBins) {
    if (numBins >= spectrumDb.length) return List.of(spectrumDb);
    return spectrumDb.sublist(0, numBins);
  }

  @override
  int startRecording(String filePath) {
    final status = _consumeStatus();
    if (status == 0) {
      _recording = true;
      recordingPath = filePath;
    }
    return status;
  }

  @override
  int startRecordingFd(int fd) {
    final status = _consumeStatus();
    if (status == 0) {
      _recording = true;
      recordingFd = fd;
    }
    return status;
  }

  @override
  int stopRecording() {
    final status = _consumeStatus();
    if (status == 0) _recording = false;
    return status;
  }

  @override
  bool get isRecording => _recording;

  @override
  int startIqRecording(String filePath) {
    final status = _consumeStatus();
    if (status == 0) {
      _iqRecording = true;
      iqRecordingPath = filePath;
    }
    return status;
  }

  @override
  int startIqRecordingFd(int fd) {
    final status = _consumeStatus();
    if (status == 0) {
      _iqRecording = true;
      iqRecordingFd = fd;
    }
    return status;
  }

  @override
  int stopIqRecording() {
    final status = _consumeStatus();
    if (status == 0) _iqRecording = false;
    return status;
  }

  @override
  bool get isIqRecording => _iqRecording;

  @override
  void dispose() {}

  int _consumeStatus() {
    if (failNextCall) {
      failNextCall = false;
      return -1;
    }
    return 0;
  }
}
