import 'dart:io';

import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:driver_rtlsdr/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Fakes path_provider's platform channel (swaps
/// [PathProviderPlatform.instance]) so [defaultRecordingPath]'s legacy-
/// Android fallback path is testable on a host with no device/emulator —
/// same spirit as [FakeRtlSdrDriver] for the native driver.
class _FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getExternalStoragePath() async => Directory.systemTemp.path;
}

void main() {
  PathProviderPlatform.instance = _FakePathProviderPlatform();

  group('RecordingController', () {
    test('startRecording applies on success', () async {
      final driver = FakeRtlSdrDriver();
      final recording = RecordingController(driver);

      await recording.startRecording('/tmp/rtlsdr_test.wav');

      expect(recording.isRecording, isTrue);
      expect(recording.currentFilePath, '/tmp/rtlsdr_test.wav');
      expect(driver.recordingPath, '/tmp/rtlsdr_test.wav');
      expect(recording.lastError, isNull);
    });

    test('startRecording records lastError on failure', () async {
      final driver = FakeRtlSdrDriver()..failNextCall = true;
      final recording = RecordingController(driver);

      await recording.startRecording('/tmp/rtlsdr_test.wav');

      expect(recording.isRecording, isFalse);
      expect(recording.lastError, isNotNull);
    });

    test('startRecording is a no-op when already recording', () async {
      final driver = FakeRtlSdrDriver();
      final recording = RecordingController(driver);
      await recording.startRecording('/tmp/a.wav');
      driver.failNextCall = true; // would fail if attempted again
      await recording.startRecording('/tmp/b.wav');
      expect(recording.currentFilePath, '/tmp/a.wav');
    });

    test('stopRecording moves currentFilePath to lastRecordingPath', () async {
      final driver = FakeRtlSdrDriver();
      final recording = RecordingController(driver);
      await recording.startRecording('/tmp/rtlsdr_test.wav');

      recording.stopRecording();

      expect(recording.isRecording, isFalse);
      expect(recording.currentFilePath, isNull);
      expect(recording.lastRecordingPath, '/tmp/rtlsdr_test.wav');
    });
  });

  group('buildRecordingFileName', () {
    test('embeds timestamp, frequency in MHz and mode short label', () {
      final name = buildRecordingFileName(
        frequencyHz: 101500000,
        mode: DemodMode.wfm,
        now: DateTime(2026, 7, 29, 14, 5, 9),
      );
      expect(name, 'rtlsdr_20260729_140509_101.500MHz_WFM.wav');
    });
  });

  group('RecordingController raw I/Q recording', () {
    test('startIqRecording applies on success', () async {
      final driver = FakeRtlSdrDriver();
      final recording = RecordingController(driver);

      await recording.startIqRecording('/tmp/rtlsdr_test.cu8');

      expect(recording.isIqRecording, isTrue);
      expect(recording.currentIqFilePath, '/tmp/rtlsdr_test.cu8');
      expect(driver.iqRecordingPath, '/tmp/rtlsdr_test.cu8');
      expect(recording.lastIqError, isNull);
    });

    test('startIqRecording records lastIqError on failure', () async {
      final driver = FakeRtlSdrDriver()..failNextCall = true;
      final recording = RecordingController(driver);

      await recording.startIqRecording('/tmp/rtlsdr_test.cu8');

      expect(recording.isIqRecording, isFalse);
      expect(recording.lastIqError, isNotNull);
    });

    test('startIqRecording is a no-op when already recording', () async {
      final driver = FakeRtlSdrDriver();
      final recording = RecordingController(driver);
      await recording.startIqRecording('/tmp/a.cu8');
      driver.failNextCall = true; // would fail if attempted again
      await recording.startIqRecording('/tmp/b.cu8');
      expect(recording.currentIqFilePath, '/tmp/a.cu8');
    });

    test(
      'stopIqRecording moves currentIqFilePath to lastIqRecordingPath',
      () async {
        final driver = FakeRtlSdrDriver();
        final recording = RecordingController(driver);
        await recording.startIqRecording('/tmp/rtlsdr_test.cu8');

        recording.stopIqRecording();

        expect(recording.isIqRecording, isFalse);
        expect(recording.currentIqFilePath, isNull);
        expect(recording.lastIqRecordingPath, '/tmp/rtlsdr_test.cu8');
      },
    );

    test('PCM and I/Q recording run independently of each other', () async {
      final driver = FakeRtlSdrDriver();
      final recording = RecordingController(driver);

      await recording.startRecording('/tmp/pcm.wav');
      await recording.startIqRecording('/tmp/raw.cu8');

      expect(recording.isRecording, isTrue);
      expect(recording.isIqRecording, isTrue);

      recording.stopRecording();

      expect(recording.isRecording, isFalse);
      expect(recording.isIqRecording, isTrue);
    });
  });

  group('buildIqRecordingFileName', () {
    test('embeds timestamp and frequency in MHz', () {
      final name = buildIqRecordingFileName(
        frequencyHz: 101500000,
        now: DateTime(2026, 7, 29, 14, 5, 9),
      );
      expect(name, 'rtlsdr_iq_20260729_140509_101.500MHz.cu8');
    });
  });

  group('RecordingController.startRecordingToDownloads', () {
    test('opens a MediaStore fd and records through it', () async {
      final driver = FakeRtlSdrDriver();
      final downloads = FakeDownloadsChannel(firstFd: 42);
      final recording = RecordingController(
        driver,
        downloadsChannel: downloads,
      );

      await recording.startRecordingToDownloads(
        frequencyHz: 101500000,
        mode: DemodMode.wfm,
      );

      expect(recording.isRecording, isTrue);
      expect(driver.recordingFd, 42);
      expect(recording.currentFilePath, startsWith('Downloads/Recordings/'));
      expect(downloads.openCalls, hasLength(1));
      expect(downloads.openCalls.single.mimeType, 'audio/wav');
      expect(downloads.openCalls.single.subdirectory, 'Recordings');
    });

    test(
      'falls back to a plain path on legacy Android (no MediaStore)',
      () async {
        final driver = FakeRtlSdrDriver();
        final downloads = FakeDownloadsChannel()..failNextOpen = true;
        final recording = RecordingController(
          driver,
          downloadsChannel: downloads,
        );

        await recording.startRecordingToDownloads(
          frequencyHz: 101500000,
          mode: DemodMode.wfm,
        );

        expect(recording.isRecording, isTrue);
        expect(driver.recordingFd, isNull);
        expect(driver.recordingPath, isNotNull);
        expect(recording.currentFilePath, driver.recordingPath);
      },
    );

    test('is a no-op when already recording', () async {
      final driver = FakeRtlSdrDriver();
      final downloads = FakeDownloadsChannel();
      final recording = RecordingController(
        driver,
        downloadsChannel: downloads,
      );
      await recording.startRecordingToDownloads(
        frequencyHz: 101500000,
        mode: DemodMode.wfm,
      );
      await recording.startRecordingToDownloads(
        frequencyHz: 200000000,
        mode: DemodMode.nfm,
      );
      expect(downloads.openCalls, hasLength(1));
    });

    test('stopRecording finalizes the MediaStore entry', () async {
      final driver = FakeRtlSdrDriver();
      final downloads = FakeDownloadsChannel(firstFd: 42);
      final recording = RecordingController(
        driver,
        downloadsChannel: downloads,
      );
      await recording.startRecordingToDownloads(
        frequencyHz: 101500000,
        mode: DemodMode.wfm,
      );

      recording.stopRecording();
      // finishDownloadsFd is fired-and-forgotten inside stopRecording — pump
      // the event loop once so it resolves before asserting.
      await Future<void>.delayed(Duration.zero);

      expect(recording.isRecording, isFalse);
      expect(downloads.finishedFds, [42]);
      expect(
        recording.lastRecordingShareUri,
        'content://media/external/downloads/42',
      );
    });
  });

  group('RecordingController.shareRecording', () {
    test('shares by URI when the last recording used Downloads', () async {
      final driver = FakeRtlSdrDriver();
      final downloads = FakeDownloadsChannel(firstFd: 7);
      final recording = RecordingController(
        driver,
        downloadsChannel: downloads,
      );
      await recording.startRecordingToDownloads(
        frequencyHz: 101500000,
        mode: DemodMode.wfm,
      );
      recording.stopRecording();
      await Future<void>.delayed(Duration.zero);

      await recording.shareRecording();

      expect(downloads.shareCalls, hasLength(1));
      expect(downloads.shareCalls.single.uri, isNotNull);
      expect(downloads.shareCalls.single.path, isNull);
      expect(downloads.shareCalls.single.mimeType, 'audio/wav');
    });

    test('shares by path when the last recording used a plain path', () async {
      final driver = FakeRtlSdrDriver();
      final downloads = FakeDownloadsChannel();
      final recording = RecordingController(
        driver,
        downloadsChannel: downloads,
      );
      await recording.startRecording('/tmp/rtlsdr_test.wav');
      recording.stopRecording();

      await recording.shareRecording();

      expect(downloads.shareCalls, hasLength(1));
      expect(downloads.shareCalls.single.uri, isNull);
      expect(downloads.shareCalls.single.path, '/tmp/rtlsdr_test.wav');
    });

    test('is a no-op when nothing has been recorded yet', () async {
      final driver = FakeRtlSdrDriver();
      final downloads = FakeDownloadsChannel();
      final recording = RecordingController(
        driver,
        downloadsChannel: downloads,
      );

      await recording.shareRecording();

      expect(downloads.shareCalls, isEmpty);
    });
  });

  group('RecordingController.startIqRecordingToDownloads', () {
    test('opens a MediaStore fd and records through it', () async {
      final driver = FakeRtlSdrDriver();
      final downloads = FakeDownloadsChannel(firstFd: 99);
      final recording = RecordingController(
        driver,
        downloadsChannel: downloads,
      );

      await recording.startIqRecordingToDownloads(frequencyHz: 101500000);

      expect(recording.isIqRecording, isTrue);
      expect(driver.iqRecordingFd, 99);
      expect(recording.currentIqFilePath, startsWith('Downloads/Recordings/'));
      expect(downloads.openCalls.single.mimeType, 'application/octet-stream');
    });

    test(
      'falls back to a plain path on legacy Android (no MediaStore)',
      () async {
        final driver = FakeRtlSdrDriver();
        final downloads = FakeDownloadsChannel()..failNextOpen = true;
        final recording = RecordingController(
          driver,
          downloadsChannel: downloads,
        );

        await recording.startIqRecordingToDownloads(frequencyHz: 101500000);

        expect(recording.isIqRecording, isTrue);
        expect(driver.iqRecordingFd, isNull);
        expect(driver.iqRecordingPath, isNotNull);
      },
    );

    test('stopIqRecording finalizes the MediaStore entry', () async {
      final driver = FakeRtlSdrDriver();
      final downloads = FakeDownloadsChannel(firstFd: 99);
      final recording = RecordingController(
        driver,
        downloadsChannel: downloads,
      );
      await recording.startIqRecordingToDownloads(frequencyHz: 101500000);

      recording.stopIqRecording();
      await Future<void>.delayed(Duration.zero);

      expect(downloads.finishedFds, [99]);
      expect(
        recording.lastIqRecordingShareUri,
        'content://media/external/downloads/99',
      );
    });
  });
}
