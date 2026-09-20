import 'dart:async';

import 'package:flutter/foundation.dart';

import '../storage/preset.dart';
import 'presets_controller.dart';
import 'radio_controller.dart';

/// A frequency with an RF signal above the threshold, found during a scan.
@immutable
class ScanHit {
  const ScanHit({
    required this.frequencyHz,
    required this.rfLevelDbfs,
    required this.timestamp,
  });

  final int frequencyHz;
  final double rfLevelDbfs;
  final DateTime timestamp;
}

/// Scans a frequency range looking for active stations: tunes each step,
/// waits for the tuner to settle (AGC/PLL), and measures the RF level (via
/// [RadioController.sampleRfLevelDbfsNow], not the already-cached
/// `rfLevelDbfs` — that only updates every [RadioController]'s stats
/// interval, too slow to stay fresh against a scan step of a few tens of
/// milliseconds) — above the threshold becomes a [ScanHit].
///
/// Mode/band agnostic: range, step and demodulation mode are caller
/// parameters — scans an NFM band (PMR, amateur radio, etc.) exactly like
/// it scans commercial WFM. Only the *default* range is commercial FM.
class ScanController extends ChangeNotifier {
  ScanController({
    this.settleDelay = const Duration(milliseconds: 50),
    this.sampleGap = const Duration(milliseconds: 20),
  });

  static const int defaultStartHz = 87500000;
  static const int defaultEndHz = 108000000;
  static const int defaultStepHz = 100000;
  static const double defaultThresholdDb = -25.0;

  /// Delay after tuning, before sampling the RF level, to let the tuner's
  /// AGC/PLL settle. Estimated default — not yet validated against real
  /// hardware; tune it if you observe missed or spurious hits.
  final Duration settleDelay;

  /// Gap between the two samples taken per step (the higher of the two is
  /// kept, to reduce the chance of sampling mid-transient).
  final Duration sampleGap;

  bool isScanning = false;
  double progress = 0.0; // 0..1
  int? currentFrequencyHz;
  List<ScanHit> results = const [];
  String? lastError;

  bool _cancelRequested = false;

  Future<void> startScan(
    RadioController radio, {
    int startHz = defaultStartHz,
    int endHz = defaultEndHz,
    int stepHz = defaultStepHz,
    double thresholdDb = defaultThresholdDb,
  }) async {
    if (isScanning) return;
    if (!radio.isStreaming) {
      lastError = 'Start streaming before scanning.';
      notifyListeners();
      return;
    }
    if (stepHz <= 0 || endHz <= startHz) {
      lastError = 'Invalid scan range.';
      notifyListeners();
      return;
    }

    isScanning = true;
    _cancelRequested = false;
    results = [];
    progress = 0.0;
    lastError = null;
    notifyListeners();

    final originalFrequencyHz = radio.frequencyHz;
    final totalSteps = ((endHz - startHz) / stepHz).ceil() + 1;
    int stepIndex = 0;
    final hits = <ScanHit>[];

    for (
      int freq = startHz;
      freq <= endHz && !_cancelRequested;
      freq += stepHz
    ) {
      currentFrequencyHz = freq;
      radio.setFrequencyHz(freq);

      await Future.delayed(settleDelay);
      if (_cancelRequested) break;

      final level1 = radio.sampleRfLevelDbfsNow();
      await Future.delayed(sampleGap);
      if (_cancelRequested) break;
      final level2 = radio.sampleRfLevelDbfsNow();
      final level = level1 > level2 ? level1 : level2;

      if (level >= thresholdDb) {
        hits.add(
          ScanHit(
            frequencyHz: freq,
            rfLevelDbfs: level,
            timestamp: DateTime.now(),
          ),
        );
        results = List.unmodifiable(hits);
      }

      stepIndex++;
      progress = (stepIndex / totalSteps).clamp(0.0, 1.0);
      notifyListeners();
    }

    isScanning = false;
    currentFrequencyHz = null;
    // A completed scan leaves the radio tuned to the last step, which is
    // expected; only restore the original frequency if cancelled midway, so
    // the radio isn't left stuck on an arbitrary frequency.
    if (_cancelRequested) {
      radio.setFrequencyHz(originalFrequencyHz);
    }
    notifyListeners();
  }

  void stopScan() {
    _cancelRequested = true;
  }

  void applyHit(RadioController radio, ScanHit hit) {
    radio.setFrequencyHz(hit.frequencyHz);
  }

  /// Saves a hit as a preset — reuses [PresetsController] entirely, no
  /// separate storage.
  void saveHitAsPreset(
    PresetsController presets,
    RadioController radio,
    ScanHit hit,
    String name,
  ) {
    presets.add(
      Preset(
        name: name,
        frequencyHz: hit.frequencyHz,
        mode: radio.demodMode,
        gainAuto: radio.gainAuto,
        gainTenthDb: radio.gainTenthDb,
      ),
    );
  }
}
