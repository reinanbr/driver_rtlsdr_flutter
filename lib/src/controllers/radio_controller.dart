import 'dart:async';

import 'package:driver_rtlsdr/driver_rtlsdr.dart' show DemodMode;
import 'package:flutter/foundation.dart';

import '../driver/rtlsdr_driver.dart';
import 'rds_controller.dart';
import 'spectrum_controller.dart';

/// Controls tuning/streaming/demodulation/gain of the dongle through an
/// [RtlSdrDriver] — once the native driver has already opened the device
/// (`deviceReady`, see `UsbState`/`UsbChannel`).
///
/// Owns [spectrumController] and [rdsController] and starts/stops them
/// together with streaming, so a UI layer only needs to listen to this one
/// controller (plus those two, for spectrum/RDS specifically) instead of
/// re-deriving that lifecycle itself.
///
/// This package deliberately does not manage a foreground service — keeping
/// the process alive while streaming with the app in the background is a
/// UX decision for each consuming app (same stance as `driver_rtlsdr`
/// itself). Use [onStreamingStarted]/[onStreamingStopped] to hook your own
/// service in.
class RadioController extends ChangeNotifier {
  RadioController(
    this.driver, {
    this.statsInterval = const Duration(milliseconds: 500),
    SpectrumController? spectrumController,
    RdsController? rdsController,
    this.onStreamingStarted,
    this.onStreamingStopped,
  }) : spectrumController = spectrumController ?? SpectrumController(driver),
       rdsController = rdsController ?? RdsController(driver);

  final RtlSdrDriver driver;
  final Duration statsInterval;

  /// Higher-rate polling of the captured band's spectrum — see
  /// [SpectrumController].
  final SpectrumController spectrumController;

  /// RDS decoding (PI/PTY/TP/TA/PS/RadioText) — see [RdsController].
  final RdsController rdsController;

  /// Called right after streaming starts successfully. Use this to start a
  /// foreground service, acquire a wake lock, etc. — whatever your app
  /// needs to keep streaming alive; this package has no opinion on it.
  final VoidCallback? onStreamingStarted;

  /// Called right after streaming stops (including from [dispose]).
  final VoidCallback? onStreamingStopped;

  int _frequencyHz = 100000000; // 100.0 MHz
  bool _isStreaming = false;
  String? lastError;

  DemodMode _demodMode = DemodMode.wfm;
  bool _gainAuto = true;
  int _gainTenthDb = 0;
  List<int> gainList = const [];

  double _squelchThresholdDb = -40.0;

  int iqBytesReceived = 0;
  int ringOverflowCount = 0;
  double bytesPerSecond = 0;
  double rfLevelDbfs = -120.0;
  double audioLevelDbfs = -90.0;
  bool squelchOpen = true;
  int recordingBytesWritten = 0;
  int iqRecordingBytesWritten = 0;

  bool _stereoEnabled = true;
  bool stereoLocked = false;
  double pilotLevel = 0.0;

  /// Bandwidth captured (spectrum span) — a waterfall/tuner widget uses this
  /// to convert a screen position into an absolute frequency. Only valid
  /// while streaming (the native driver only changes the sample rate while
  /// the device is open and not streaming); updated in [startStreaming].
  int sampleRateHz = 1024000;

  int _lastIqBytes = 0;
  DateTime? _lastPollTime;

  Timer? _statsTimer;

  int get frequencyHz => _frequencyHz;
  bool get isStreaming => _isStreaming;
  DemodMode get demodMode => _demodMode;
  bool get gainAuto => _gainAuto;
  int get gainTenthDb => _gainTenthDb;
  double get squelchThresholdDb => _squelchThresholdDb;
  bool get stereoEnabled => _stereoEnabled;

  void setFrequencyHz(int hz) {
    final status = driver.setFrequencyHz(hz);
    if (status == 0) {
      _frequencyHz = hz;
      lastError = null;
    } else {
      lastError = 'Failed to set frequency (status $status)';
    }
    notifyListeners();
  }

  /// Changes the demodulation mode. The native DSP thread only reads the
  /// mode when streaming starts, so if already streaming this restarts it
  /// to apply the change immediately.
  void setDemodMode(DemodMode mode) {
    final status = driver.setDemodMode(mode);
    if (status != 0) {
      lastError = 'Failed to set demod mode (status $status)';
      notifyListeners();
      return;
    }
    _demodMode = mode;
    lastError = null;
    if (_isStreaming) {
      stopStreaming();
      startStreaming();
    } else {
      notifyListeners();
    }
  }

  void setGainAuto(bool auto) {
    final status = driver.setGainMode(auto: auto);
    if (status == 0) {
      _gainAuto = auto;
      lastError = null;
    } else {
      lastError = 'Failed to set gain mode (status $status)';
    }
    notifyListeners();
  }

  void setGainTenthDb(int gainTenthsDb) {
    final status = driver.setGainTenthDb(gainTenthsDb);
    if (status == 0) {
      _gainTenthDb = gainTenthsDb;
      _gainAuto = false;
      lastError = null;
    } else {
      lastError = 'Failed to set gain (status $status)';
    }
    notifyListeners();
  }

  /// Fetches the list of gains supported by the tuner (tenths of a dB).
  /// Needs the dongle already open (`deviceReady`) — call once after that.
  void refreshGainList() {
    final gains = driver.getGainList();
    if (gains.isNotEmpty) {
      gainList = gains;
      notifyListeners();
    }
  }

  void setSquelchThresholdDb(double thresholdDb) {
    final status = driver.setSquelchThresholdDb(thresholdDb);
    if (status == 0) {
      _squelchThresholdDb = thresholdDb;
      lastError = null;
    } else {
      lastError = 'Failed to set squelch (status $status)';
    }
    notifyListeners();
  }

  /// Toggles the stereo demux (WFM only). Unlike [setDemodMode], applied
  /// live — the native DSP thread reads this every block, no need to
  /// stop/restart streaming.
  void setStereoEnabled(bool enabled) {
    final status = driver.setStereoEnabled(enabled);
    if (status == 0) {
      _stereoEnabled = enabled;
      lastError = null;
    } else {
      lastError = 'Failed to set stereo (status $status)';
    }
    notifyListeners();
  }

  void startStreaming() {
    if (_isStreaming) return;
    final status = driver.startStreaming();
    if (status == 0) {
      _isStreaming = true;
      lastError = null;
      _lastIqBytes = 0;
      _lastPollTime = null;
      bytesPerSecond = 0;
      sampleRateHz = driver.sampleRateHz;
      _statsTimer?.cancel();
      _statsTimer = Timer.periodic(statsInterval, (_) => refreshStats());
      spectrumController.start();
      rdsController.start();
      onStreamingStarted?.call();
    } else {
      lastError = 'Failed to start streaming (status $status)';
    }
    notifyListeners();
  }

  void stopStreaming() {
    if (!_isStreaming) return;
    final status = driver.stopStreaming();
    _statsTimer?.cancel();
    _statsTimer = null;
    spectrumController.stop();
    rdsController.stop();
    onStreamingStopped?.call();
    if (status == 0) {
      _isStreaming = false;
      lastError = null;
    } else {
      lastError = 'Failed to stop streaming (status $status)';
    }
    notifyListeners();
  }

  /// Polls stats immediately, outside the periodic timer — also what the
  /// internal timer calls. Updates `bytesPerSecond` from the elapsed time
  /// since the last poll.
  void refreshStats() {
    final stats = driver.getStats();

    final now = DateTime.now();
    final lastPollTime = _lastPollTime;
    if (lastPollTime != null) {
      final dtSeconds = now.difference(lastPollTime).inMicroseconds / 1e6;
      if (dtSeconds > 0) {
        bytesPerSecond = (stats.iqBytesReceived - _lastIqBytes) / dtSeconds;
      }
    }
    _lastIqBytes = stats.iqBytesReceived;
    _lastPollTime = now;

    iqBytesReceived = stats.iqBytesReceived;
    ringOverflowCount = stats.ringOverflowCount;
    rfLevelDbfs = stats.rfLevelDbfs;
    audioLevelDbfs = stats.audioLevelDbfs;
    squelchOpen = stats.squelchOpen;
    recordingBytesWritten = stats.recordingBytesWritten;
    iqRecordingBytesWritten = stats.iqRecordingBytesWritten;
    stereoLocked = stats.stereoLocked;
    pilotLevel = stats.pilotLevel;
    notifyListeners();
  }

  /// Immediate sample of `rfLevelDbfs`, without waiting for the next
  /// periodic tick — used by [ScanController], which needs to sample much
  /// faster than the normal polling interval during a scan. Updates the
  /// level/squelch fields (the UI reflects the scan live if visible), but
  /// deliberately does NOT touch `iqBytesReceived`/the `bytesPerSecond`
  /// bookkeeping — sampling outside the periodic timer's interval would
  /// skew that rate.
  double sampleRfLevelDbfsNow() {
    final stats = driver.getStats();
    rfLevelDbfs = stats.rfLevelDbfs;
    audioLevelDbfs = stats.audioLevelDbfs;
    squelchOpen = stats.squelchOpen;
    notifyListeners();
    return rfLevelDbfs;
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    if (_isStreaming) {
      driver.stopStreaming();
      onStreamingStopped?.call();
    }
    spectrumController.dispose();
    rdsController.dispose();
    super.dispose();
  }
}
