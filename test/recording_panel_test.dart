import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:driver_rtlsdr/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeRtlSdrDriver driver;
  late RadioController radio;
  late RecordingController recording;

  setUp(() {
    driver = FakeRtlSdrDriver();
    radio = RadioController(driver)..startStreaming();
    recording = RecordingController(driver);
  });

  tearDown(() => radio.dispose());

  Widget harness() {
    return MaterialApp(
      home: Scaffold(
        body: RecordingPanel(
          radio: radio,
          recording: recording,
          buildFilePath: () async => '/tmp/pcm.wav',
          buildIqFilePath: () async => '/tmp/iq.cu8',
        ),
      ),
    );
  }

  testWidgets('both record buttons disabled while not streaming', (
    tester,
  ) async {
    radio.stopStreaming();
    await tester.pumpWidget(harness());

    for (final button in tester.widgetList<FilledButton>(
      find.byType(FilledButton),
    )) {
      expect(button.onPressed, isNull);
    }
  });

  testWidgets('Record PCM starts PCM recording only', (tester) async {
    await tester.pumpWidget(harness());

    await tester.tap(find.text('Record PCM'));
    await tester.pumpAndSettle();

    expect(recording.isRecording, isTrue);
    expect(recording.currentFilePath, '/tmp/pcm.wav');
    expect(recording.isIqRecording, isFalse);
    expect(find.textContaining('PCM: /tmp/pcm.wav'), findsOneWidget);
    expect(find.text('Stop PCM'), findsOneWidget);
  });

  testWidgets('Record I/Q starts I/Q recording only', (tester) async {
    await tester.pumpWidget(harness());

    await tester.tap(find.text('Record I/Q'));
    await tester.pumpAndSettle();

    expect(recording.isIqRecording, isTrue);
    expect(recording.currentIqFilePath, '/tmp/iq.cu8');
    expect(recording.isRecording, isFalse);
    expect(find.textContaining('I/Q: /tmp/iq.cu8'), findsOneWidget);
    expect(find.text('Stop I/Q'), findsOneWidget);
  });

  testWidgets('PCM and I/Q recording run independently at the same time', (
    tester,
  ) async {
    await tester.pumpWidget(harness());

    await tester.tap(find.text('Record PCM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record I/Q'));
    await tester.pumpAndSettle();

    expect(recording.isRecording, isTrue);
    expect(recording.isIqRecording, isTrue);

    await tester.tap(find.text('Stop PCM'));
    await tester.pumpAndSettle();

    expect(recording.isRecording, isFalse);
    expect(recording.isIqRecording, isTrue);
    expect(find.textContaining('PCM saved: /tmp/pcm.wav'), findsOneWidget);
  });

  group('default (Downloads) flow, no buildFilePath override', () {
    late FakeDownloadsChannel downloads;

    setUp(() {
      downloads = FakeDownloadsChannel(firstFd: 500);
      recording = RecordingController(driver, downloadsChannel: downloads);
    });

    Widget defaultHarness() {
      return MaterialApp(
        home: Scaffold(
          body: RecordingPanel(radio: radio, recording: recording),
        ),
      );
    }

    testWidgets('Record PCM records into Downloads via MediaStore', (
      tester,
    ) async {
      await tester.pumpWidget(defaultHarness());

      await tester.tap(find.text('Record PCM'));
      await tester.pumpAndSettle();

      expect(recording.isRecording, isTrue);
      expect(driver.recordingFd, 500);
      expect(downloads.openCalls, hasLength(1));
      expect(find.textContaining('Downloads/Recordings/'), findsOneWidget);
    });

    testWidgets('Record I/Q records into Downloads via MediaStore', (
      tester,
    ) async {
      await tester.pumpWidget(defaultHarness());

      await tester.tap(find.text('Record I/Q'));
      await tester.pumpAndSettle();

      expect(recording.isIqRecording, isTrue);
      expect(driver.iqRecordingFd, 500);
      expect(downloads.openCalls.single.mimeType, 'application/octet-stream');
    });

    testWidgets('share button shares the last completed PCM recording', (
      tester,
    ) async {
      await tester.pumpWidget(defaultHarness());
      await tester.tap(find.text('Record PCM'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop PCM'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.share));
      await tester.pumpAndSettle();

      expect(downloads.shareCalls, hasLength(1));
      expect(downloads.shareCalls.single.uri, isNotNull);
      expect(downloads.shareCalls.single.mimeType, 'audio/wav');
    });
  });
}
