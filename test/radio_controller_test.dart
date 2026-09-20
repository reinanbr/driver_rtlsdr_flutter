import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:driver_rtlsdr/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RadioController', () {
    test('setFrequencyHz applies on success and clears lastError', () {
      final driver = FakeRtlSdrDriver();
      final radio = RadioController(driver);
      radio.setFrequencyHz(101500000);
      expect(radio.frequencyHz, 101500000);
      expect(driver.frequencyHz, 101500000);
      expect(radio.lastError, isNull);
    });

    test('setFrequencyHz records lastError and keeps old value on failure', () {
      final driver = FakeRtlSdrDriver()..failNextCall = true;
      final radio = RadioController(driver);
      radio.setFrequencyHz(101500000);
      expect(radio.frequencyHz, 100000000); // unchanged (default)
      expect(radio.lastError, isNotNull);
    });

    test('startStreaming/stopStreaming toggle state and sub-controllers', () {
      final driver = FakeRtlSdrDriver();
      final radio = RadioController(driver);

      radio.startStreaming();
      expect(radio.isStreaming, isTrue);
      expect(driver.isStreaming, isTrue);

      radio.stopStreaming();
      expect(radio.isStreaming, isFalse);
      expect(driver.isStreaming, isFalse);
    });

    test('startStreaming is a no-op when already streaming', () {
      final driver = FakeRtlSdrDriver();
      final radio = RadioController(driver);
      radio.startStreaming();
      driver.failNextCall = true; // would fail if attempted again
      radio.startStreaming();
      expect(radio.isStreaming, isTrue);
      expect(radio.lastError, isNull);
    });

    test('onStreamingStarted/onStreamingStopped hooks fire', () {
      final driver = FakeRtlSdrDriver();
      var started = 0;
      var stopped = 0;
      final radio = RadioController(
        driver,
        onStreamingStarted: () => started++,
        onStreamingStopped: () => stopped++,
      );
      radio.startStreaming();
      expect(started, 1);
      radio.stopStreaming();
      expect(stopped, 1);
    });

    test('setDemodMode restarts streaming to apply immediately', () {
      final driver = FakeRtlSdrDriver();
      final radio = RadioController(driver);
      radio.startStreaming();

      radio.setDemodMode(DemodMode.nfm);

      expect(radio.demodMode, DemodMode.nfm);
      expect(driver.demodMode, DemodMode.nfm);
      // Restarted, so still streaming afterwards.
      expect(radio.isStreaming, isTrue);
    });

    test('setDemodMode does not touch streaming when not streaming', () {
      final driver = FakeRtlSdrDriver();
      final radio = RadioController(driver);
      radio.setDemodMode(DemodMode.am);
      expect(radio.demodMode, DemodMode.am);
      expect(radio.isStreaming, isFalse);
    });

    test('setGainTenthDb switches gainAuto off', () {
      final driver = FakeRtlSdrDriver();
      final radio = RadioController(driver);
      radio.setGainAuto(true);
      radio.setGainTenthDb(197);
      expect(radio.gainTenthDb, 197);
      expect(radio.gainAuto, isFalse);
    });

    test('refreshGainList populates from the driver', () {
      final driver = FakeRtlSdrDriver();
      final radio = RadioController(driver);
      radio.refreshGainList();
      expect(radio.gainList, isNotEmpty);
      expect(radio.gainList, driver.gainList);
    });

    test('setSquelchThresholdDb applies on success', () {
      final driver = FakeRtlSdrDriver();
      final radio = RadioController(driver);
      radio.setSquelchThresholdDb(-30);
      expect(radio.squelchThresholdDb, -30);
    });

    test('setStereoEnabled applies live without touching streaming', () {
      final driver = FakeRtlSdrDriver();
      final radio = RadioController(driver);
      radio.startStreaming();
      radio.setStereoEnabled(false);
      expect(radio.stereoEnabled, isFalse);
      expect(radio.isStreaming, isTrue);
    });

    test(
      'refreshStats copies driver stats and computes bytesPerSecond',
      () async {
        final driver = FakeRtlSdrDriver();
        final radio = RadioController(driver);
        radio.startStreaming();

        driver.iqBytesReceived = 1000;
        radio.refreshStats();
        expect(radio.iqBytesReceived, 1000);

        await Future<void>.delayed(const Duration(milliseconds: 20));
        driver.iqBytesReceived = 3000;
        radio.refreshStats();

        expect(radio.iqBytesReceived, 3000);
        expect(radio.bytesPerSecond, greaterThan(0));
      },
    );

    test(
      'refreshStats copies iqRecordingBytesWritten independent of PCM recordingBytesWritten',
      () {
        final driver = FakeRtlSdrDriver();
        final radio = RadioController(driver);
        radio.startStreaming();

        driver.recordingBytesWritten = 500;
        driver.iqRecordingBytesWritten = 2000;
        radio.refreshStats();

        expect(radio.recordingBytesWritten, 500);
        expect(radio.iqRecordingBytesWritten, 2000);
      },
    );

    test(
      'sampleRfLevelDbfsNow updates level but not iqBytesReceived bookkeeping',
      () {
        final driver = FakeRtlSdrDriver();
        final radio = RadioController(driver);
        radio.startStreaming();
        driver.iqBytesReceived = 5000;
        radio.refreshStats();

        driver.rfLevelDbfs = -5;
        driver.iqBytesReceived =
            999999; // should not affect bytesPerSecond math
        final level = radio.sampleRfLevelDbfsNow();

        expect(level, -5);
        expect(radio.rfLevelDbfs, -5);
        expect(
          radio.iqBytesReceived,
          5000,
        ); // untouched by the immediate sample
      },
    );

    test('dispose stops streaming and fires onStreamingStopped', () {
      final driver = FakeRtlSdrDriver();
      var stopped = 0;
      final radio = RadioController(
        driver,
        onStreamingStopped: () => stopped++,
      );
      radio.startStreaming();
      radio.dispose();
      expect(driver.isStreaming, isFalse);
      expect(stopped, 1);
    });
  });
}
