import 'package:flutter/services.dart';

/// Bridge to the Kotlin side for saving recordings into Android's public
/// Downloads folder (via `MediaStore.Downloads`) and sharing a recording
/// through the native share sheet — Kotlin (`DriverRtlsdrPlugin`) is the
/// only part of the driver that can talk to `ContentResolver`/
/// `Intent.ACTION_SEND`.
///
/// [openDownloadsFd] only works on Android 10 (API 29) or higher — the
/// `MediaStore.Downloads` collection doesn't exist on older versions, and
/// there's no plain filesystem path into the public Downloads folder to
/// fall back to there. Callers should catch the [PlatformException] this
/// throws and fall back to their own app-specific-storage default instead
/// (see `core_rtlsdr`'s `RecordingController.startRecordingToDownloads`).
class DownloadsChannel {
  static const MethodChannel _methods = MethodChannel('driver_rtlsdr');

  /// Opens a writable file descriptor for `Downloads/$subdirectory/$fileName`
  /// via MediaStore, returning the raw fd — pass it straight into
  /// `NativeBindings.shimStartRecordingFd`/`shimStartIqRecordingFd`. The
  /// entry stays hidden from other apps (`IS_PENDING`) until
  /// [finishDownloadsFd] is called.
  Future<int> openDownloadsFd({
    required String fileName,
    required String mimeType,
    String subdirectory = 'Recordings',
  }) async {
    final fd = await _methods.invokeMethod<int>('openDownloadsFd', {
      'fileName': fileName,
      'mimeType': mimeType,
      'subdirectory': subdirectory,
    });
    if (fd == null) {
      throw PlatformException(
        code: 'OPEN_DOWNLOADS_FD_FAILED',
        message: 'openDownloadsFd returned no file descriptor',
      );
    }
    return fd;
  }

  /// Finalizes a recording opened via [openDownloadsFd] — clears
  /// `IS_PENDING` so it becomes visible to other apps — and returns its
  /// `content://` URI (for a later [shareFile] call), or null if `fd`
  /// wasn't tracked (only call this for recordings that actually used
  /// [openDownloadsFd]).
  Future<String?> finishDownloadsFd(int fd) {
    return _methods.invokeMethod<String>('finishDownloadsFd', {'fd': fd});
  }

  /// Shares a recording via Android's native chooser. Pass [uri] (a
  /// `content://` URI, from a MediaStore/Downloads recording) if you have
  /// one; otherwise pass [path] (a plain file — the legacy fallback or a
  /// developer's own chosen directory), which gets resolved to a shareable
  /// URI via a bundled `FileProvider` first. Exactly one of [uri]/[path]
  /// must be given.
  Future<void> shareFile({String? uri, String? path, required String mimeType}) {
    assert((uri == null) != (path == null), 'Pass exactly one of uri or path');
    return _methods.invokeMethod<void>('shareFile', {
      'uri': uri,
      'path': path,
      'mimeType': mimeType,
    });
  }
}
