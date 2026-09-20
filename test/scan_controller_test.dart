import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:driver_rtlsdr/testing.dart';
import 'package:flutter_test/flutter_test.dart';

RadioController _streamingRadio({
  double Function(int)? signalLevelForFrequency,
}) {
  final driver = FakeRtlSdrDriver(
    signalLevelForFrequency: signalLevelForFrequency,
  );
  final radio = RadioController(driver);
  radio.startStreaming();
  return radio;
}

ScanController _fastScanner() =>
    ScanController(settleDelay: Duration.zero, sampleGap: Duration.zero);

void main() {
  group('ScanController', () {
    test('refuses to scan when the radio is not streaming', () async {
      final driver = FakeRtlSdrDriver();
      final radio = RadioController(driver);
      final scanner = _fastScanner();

      await scanner.startScan(radio, startHz: 100, endHz: 200, stepHz: 100);

      expect(scanner.isScanning, isFalse);
      expect(scanner.lastError, isNotNull);
      expect(scanner.results, isEmpty);
    });

    test('rejects an invalid range', () async {
      final radio = _streamingRadio();
      final scanner = _fastScanner();

      await scanner.startScan(radio, startHz: 200, endHz: 100, stepHz: 100);

      expect(scanner.lastError, isNotNull);
    });

    test('finds hits above the threshold and skips the rest', () async {
      final hot = {100200000, 100500000};
      final radio = _streamingRadio(
        signalLevelForFrequency: (hz) => hot.contains(hz) ? -10.0 : -80.0,
      );
      final scanner = _fastScanner();

      await scanner.startScan(
        radio,
        startHz: 100000000,
        endHz: 100600000,
        stepHz: 100000,
        thresholdDb: -25,
      );

      expect(scanner.isScanning, isFalse);
      expect(scanner.results.map((h) => h.frequencyHz).toSet(), {
        100200000,
        100500000,
      });
      for (final hit in scanner.results) {
        expect(hit.rfLevelDbfs, -10.0);
      }
    });

    test('a completed scan leaves the radio tuned to the last step', () async {
      final radio = _streamingRadio();
      final scanner = _fastScanner();

      await scanner.startScan(
        radio,
        startHz: 100000000,
        endHz: 100200000,
        stepHz: 100000,
      );

      expect(radio.frequencyHz, 100200000);
    });

    test('applyHit tunes the radio to the hit frequency', () {
      final radio = _streamingRadio();
      final scanner = _fastScanner();
      final hit = ScanHit(
        frequencyHz: 103700000,
        rfLevelDbfs: -12,
        timestamp: DateTime.now(),
      );
      scanner.applyHit(radio, hit);
      expect(radio.frequencyHz, 103700000);
    });

    test('saveHitAsPreset stores the hit via PresetsController', () async {
      final radio = _streamingRadio();
      radio.setDemodMode(DemodMode.wfm);
      final scanner = _fastScanner();
      final presets = PresetsController(InMemoryPresetsRepository());
      final hit = ScanHit(
        frequencyHz: 103700000,
        rfLevelDbfs: -12,
        timestamp: DateTime.now(),
      );

      scanner.saveHitAsPreset(presets, radio, hit, 'My station');
      // add() persists asynchronously; give it a tick.
      await Future<void>.delayed(Duration.zero);

      expect(presets.presets, hasLength(1));
      expect(presets.presets.first.name, 'My station');
      expect(presets.presets.first.frequencyHz, 103700000);
    });
  });
}
