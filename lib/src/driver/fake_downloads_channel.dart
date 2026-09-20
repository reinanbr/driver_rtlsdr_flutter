import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter/services.dart';

/// In-memory [DownloadsChannel] with no platform-channel dependency — for
/// unit-testing `RecordingController.startRecordingToDownloads`/
/// `startIqRecordingToDownloads`/`shareRecording` without an Android device.
///
/// Hands out incrementing fake fds starting at [firstFd] and tracks every
/// call so a test can assert on the filenames/mime types/subdirectories used
/// and what got shared.
class FakeDownloadsChannel extends DownloadsChannel {
  FakeDownloadsChannel({this.firstFd = 1000});

  final int firstFd;
  int _nextFd = 0;

  /// Set to make the next [openDownloadsFd] call fail — simulates the
  /// legacy-Android (pre-API 29) fallback path, where there's no
  /// `MediaStore.Downloads` collection to insert into.
  bool failNextOpen = false;

  final List<({String fileName, String mimeType, String subdirectory})>
  openCalls = [];
  final List<int> finishedFds = [];
  final List<({String? uri, String? path, String mimeType})> shareCalls = [];

  @override
  Future<int> openDownloadsFd({
    required String fileName,
    required String mimeType,
    String subdirectory = 'Recordings',
  }) async {
    openCalls.add((
      fileName: fileName,
      mimeType: mimeType,
      subdirectory: subdirectory,
    ));
    if (failNextOpen) {
      failNextOpen = false;
      throw PlatformException(code: 'OPEN_DOWNLOADS_FD_FAILED');
    }
    final fd = firstFd + _nextFd;
    _nextFd++;
    return fd;
  }

  @override
  Future<String?> finishDownloadsFd(int fd) async {
    finishedFds.add(fd);
    return 'content://media/external/downloads/$fd';
  }

  @override
  Future<void> shareFile({
    String? uri,
    String? path,
    required String mimeType,
  }) async {
    shareCalls.add((uri: uri, path: path, mimeType: mimeType));
  }
}
