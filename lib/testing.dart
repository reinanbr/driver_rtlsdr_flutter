/// Test doubles for `driver_rtlsdr` — import this (never `dart:ffi` directly)
/// to test radio logic or UI built on top of this package without an
/// Android device, an emulator, or a dongle.
///
/// ```dart
/// final driver = FakeRtlSdrDriver();
/// final radio = RadioController(driver);
/// radio.startStreaming();
/// driver.rfLevelDbfs = -10; // simulate a strong signal
/// radio.refreshStats();
/// expect(radio.rfLevelDbfs, -10);
/// ```
library;

export 'src/driver/fake_downloads_channel.dart';
export 'src/driver/fake_rtlsdr_driver.dart';
export 'src/storage/in_memory_presets_repository.dart';
