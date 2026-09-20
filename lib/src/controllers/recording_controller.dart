import 'dart:async';
import 'dart:io';

import 'package:driver_rtlsdr/driver_rtlsdr.dart'
    show DemodMode, DownloadsChannel;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../driver/rtlsdr_driver.dart';

/// Records the same PCM already going to the speaker to a WAV file, via
/// [RtlSdrDriver.startRecording]/[stopRecording] — the tap happens inside
/// the native DSP thread; this only orchestrates the file path and state
/// for the UI.
///
/// Three ways to choose *where* a recording goes:
/// - [startRecording]/[startIqRecording]: pass an absolute path yourself
///   (see [defaultRecordingPath] for a ready-made one under app-specific
///   external storage, no runtime storage permission needed on modern
///   Android).
/// - [startRecordingToDownloads]/[startIqRecordingToDownloads]: the public
///   Downloads folder, via Android's `MediaStore` (API 29+ — falls back to
///   [startRecording]/[startIqRecording] automatically on older versions,
///   since there's no `MediaStore.Downloads` collection to insert into
///   there and no plain path into that folder either).
///
/// [shareRecording]/[shareIqRecording] share the most recently completed
/// recording (whichever of the above started it) through Android's native
/// share sheet.
class RecordingController extends ChangeNotifier {
  RecordingController(this.driver, {DownloadsChannel? downloadsChannel})
    : downloadsChannel = downloadsChannel ?? DownloadsChannel();

  final RtlSdrDriver driver;
  final DownloadsChannel downloadsChannel;

  bool isRecording = false;
  String? currentFilePath;
  String? lastRecordingPath;
  DateTime? recordingStartTime;
  String? lastError;
  int? _currentFd;

  /// `content://` URI of the last recording started via
  /// [startRecordingToDownloads], once [stopRecording] has finalized it —
  /// null for a recording started via [startRecording] or the
  /// legacy-Android fallback (those share by [lastRecordingPath] instead,
  /// see [shareRecording]).
  String? lastRecordingShareUri;

  /// Raw I/Q ".cu8" recording — independent of the demodulated-PCM
  /// recording above (see [RtlSdrDriver.startIqRecording]); both can run at
  /// once.
  bool isIqRecording = false;
  String? currentIqFilePath;
  String? lastIqRecordingPath;
  DateTime? iqRecordingStartTime;
  String? lastIqError;
  int? _currentIqFd;

  /// Same as [lastRecordingShareUri], for the last I/Q recording.
  String? lastIqRecordingShareUri;

  Future<void> startRecording(String filePath) async {
    if (isRecording) return;
    final status = driver.startRecording(filePath);
    if (status == 0) {
      isRecording = true;
      currentFilePath = filePath;
      recordingStartTime = DateTime.now();
      lastError = null;
    } else {
      lastError = 'Failed to start recording (status $status)';
    }
    notifyListeners();
  }

  /// Records into the public Downloads folder (`Downloads/$subdirectory/`)
  /// via [downloadsChannel], instead of app-specific storage. Falls back to
  /// [startRecording] + [defaultRecordingPath] on any failure opening the
  /// MediaStore entry (in practice: Android below API 29) — the feature
  /// degrades gracefully rather than erroring out.
  Future<void> startRecordingToDownloads({
    required int frequencyHz,
    required DemodMode mode,
    String subdirectory = 'Recordings',
  }) async {
    if (isRecording) return;
    final fileName = buildRecordingFileName(
      frequencyHz: frequencyHz,
      mode: mode,
    );
    final int fd;
    try {
      fd = await downloadsChannel.openDownloadsFd(
        fileName: fileName,
        mimeType: 'audio/wav',
        subdirectory: subdirectory,
      );
    } catch (_) {
      final path = await defaultRecordingPath(
        frequencyHz: frequencyHz,
        mode: mode,
        subdirectory: subdirectory,
      );
      await startRecording(path);
      return;
    }

    final status = driver.startRecordingFd(fd);
    if (status == 0) {
      isRecording = true;
      currentFilePath = 'Downloads/$subdirectory/$fileName';
      _currentFd = fd;
      recordingStartTime = DateTime.now();
      lastError = null;
    } else {
      lastError = 'Failed to start recording (status $status)';
    }
    notifyListeners();
  }

  void stopRecording() {
    if (!isRecording) return;
    final status = driver.stopRecording();
    final fd = _currentFd;
    if (status == 0) {
      lastRecordingPath = currentFilePath;
      lastError = null;
    } else {
      lastError = 'Failed to stop recording (status $status)';
    }
    isRecording = false;
    currentFilePath = null;
    _currentFd = null;
    recordingStartTime = null;
    notifyListeners();
    if (status == 0 && fd != null) {
      unawaited(_finishRecordingDownload(fd));
    }
  }

  Future<void> _finishRecordingDownload(int fd) async {
    lastRecordingShareUri = await downloadsChannel.finishDownloadsFd(fd);
    notifyListeners();
  }

  /// Shares the last completed PCM recording via Android's native share
  /// sheet — a Downloads recording ([lastRecordingShareUri]) shares
  /// directly; a plain-path recording ([lastRecordingPath]) is resolved to
  /// a shareable URI by [downloadsChannel] first. No-op if there's nothing
  /// to share yet.
  Future<void> shareRecording() {
    final uri = lastRecordingShareUri;
    if (uri != null) {
      return downloadsChannel.shareFile(uri: uri, mimeType: 'audio/wav');
    }
    final path = lastRecordingPath;
    if (path == null) return Future.value();
    return downloadsChannel.shareFile(path: path, mimeType: 'audio/wav');
  }

  Future<void> startIqRecording(String filePath) async {
    if (isIqRecording) return;
    final status = driver.startIqRecording(filePath);
    if (status == 0) {
      isIqRecording = true;
      currentIqFilePath = filePath;
      iqRecordingStartTime = DateTime.now();
      lastIqError = null;
    } else {
      lastIqError = 'Failed to start I/Q recording (status $status)';
    }
    notifyListeners();
  }

  /// Same as [startRecordingToDownloads], for raw I/Q recording.
  Future<void> startIqRecordingToDownloads({
    required int frequencyHz,
    String subdirectory = 'Recordings',
  }) async {
    if (isIqRecording) return;
    final fileName = buildIqRecordingFileName(frequencyHz: frequencyHz);
    final int fd;
    try {
      fd = await downloadsChannel.openDownloadsFd(
        fileName: fileName,
        mimeType: 'application/octet-stream',
        subdirectory: subdirectory,
      );
    } catch (_) {
      final path = await defaultIqRecordingPath(
        frequencyHz: frequencyHz,
        subdirectory: subdirectory,
      );
      await startIqRecording(path);
      return;
    }

    final status = driver.startIqRecordingFd(fd);
    if (status == 0) {
      isIqRecording = true;
      currentIqFilePath = 'Downloads/$subdirectory/$fileName';
      _currentIqFd = fd;
      iqRecordingStartTime = DateTime.now();
      lastIqError = null;
    } else {
      lastIqError = 'Failed to start I/Q recording (status $status)';
    }
    notifyListeners();
  }

  void stopIqRecording() {
    if (!isIqRecording) return;
    final status = driver.stopIqRecording();
    final fd = _currentIqFd;
    if (status == 0) {
      lastIqRecordingPath = currentIqFilePath;
      lastIqError = null;
    } else {
      lastIqError = 'Failed to stop I/Q recording (status $status)';
    }
    isIqRecording = false;
    currentIqFilePath = null;
    _currentIqFd = null;
    iqRecordingStartTime = null;
    notifyListeners();
    if (status == 0 && fd != null) {
      unawaited(_finishIqRecordingDownload(fd));
    }
  }

  Future<void> _finishIqRecordingDownload(int fd) async {
    lastIqRecordingShareUri = await downloadsChannel.finishDownloadsFd(fd);
    notifyListeners();
  }

  /// Same as [shareRecording], for the last completed I/Q recording.
  Future<void> shareIqRecording() {
    final uri = lastIqRecordingShareUri;
    if (uri != null) {
      return downloadsChannel.shareFile(
        uri: uri,
        mimeType: 'application/octet-stream',
      );
    }
    final path = lastIqRecordingPath;
    if (path == null) return Future.value();
    return downloadsChannel.shareFile(
      path: path,
      mimeType: 'application/octet-stream',
    );
  }
}

/// Builds a timestamped WAV path under app-specific external storage
/// (`<external>/[subdirectory]/rtlsdr_<timestamp>_<freq>MHz_<mode>.wav`),
/// creating the directory if needed. A convenience for the common case —
/// apps with different naming/location needs can build their own path and
/// call [RecordingController.startRecording] directly instead.
Future<String> defaultRecordingPath({
  required int frequencyHz,
  required DemodMode mode,
  String subdirectory = 'Recordings',
}) async {
  final baseDir = await getExternalStorageDirectory();
  if (baseDir == null) {
    throw StateError('External storage is unavailable on this device');
  }
  final recordingsDir = Directory('${baseDir.path}/$subdirectory');
  await recordingsDir.create(recursive: true);

  final fileName = buildRecordingFileName(frequencyHz: frequencyHz, mode: mode);
  return '${recordingsDir.path}/$fileName';
}

/// Builds the `rtlsdr_<timestamp>_<freq>MHz_<mode>.wav` file name used by
/// [defaultRecordingPath] — split out as a pure function (no `dart:io`) so
/// it's unit-testable without a platform to resolve a directory against.
String buildRecordingFileName({
  required int frequencyHz,
  required DemodMode mode,
  DateTime? now,
}) {
  final t = now ?? DateTime.now();
  final freqMhz = (frequencyHz / 1e6).toStringAsFixed(3);
  String two(int n) => n.toString().padLeft(2, '0');
  final timestamp =
      '${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}';
  return 'rtlsdr_${timestamp}_${freqMhz}MHz_${mode.shortLabel}.wav';
}

/// Builds a timestamped raw I/Q path under app-specific external storage
/// (`<external>/[subdirectory]/rtlsdr_iq_<timestamp>_<freq>MHz.cu8`),
/// creating the directory if needed. Raw I/Q capture happens before
/// demodulation, so unlike [defaultRecordingPath] there is no demod mode to
/// embed in the name.
Future<String> defaultIqRecordingPath({
  required int frequencyHz,
  String subdirectory = 'Recordings',
}) async {
  final baseDir = await getExternalStorageDirectory();
  if (baseDir == null) {
    throw StateError('External storage is unavailable on this device');
  }
  final recordingsDir = Directory('${baseDir.path}/$subdirectory');
  await recordingsDir.create(recursive: true);

  final fileName = buildIqRecordingFileName(frequencyHz: frequencyHz);
  return '${recordingsDir.path}/$fileName';
}

/// Builds the `rtlsdr_iq_<timestamp>_<freq>MHz.cu8` file name used by
/// [defaultIqRecordingPath] — split out as a pure function (no `dart:io`) so
/// it's unit-testable without a platform to resolve a directory against.
/// `.cu8` matches the interleaved 8-bit unsigned I/Q format `rtl_sdr`/GNU
/// Radio/gqrx use for raw captures.
String buildIqRecordingFileName({required int frequencyHz, DateTime? now}) {
  final t = now ?? DateTime.now();
  final freqMhz = (frequencyHz / 1e6).toStringAsFixed(3);
  String two(int n) => n.toString().padLeft(2, '0');
  final timestamp =
      '${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}';
  return 'rtlsdr_iq_${timestamp}_${freqMhz}MHz.cu8';
}
