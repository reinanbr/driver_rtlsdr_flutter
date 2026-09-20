## 0.3.2

- Fixed `SpectrumScope`/`SpectrumTuner` drag-to-tune: it used to retune to
  the finger's *absolute* position on every drag update, which made a
  slow, deliberate sweep across the band impossible — the smallest hand
  tremor and the whole visible span jumped. Dragging now pans by the
  incremental *delta* instead (drag right "pulls" lower frequencies
  toward the center, like panning a horizontal list), restoring the feel
  of the original pre-merge app widget this regressed from. Tap-to-tune
  (retune exactly under a single tap) is unchanged.
- Added `FrequencyReadout.minStepHz`: sets the Hz value of the *rightmost*
  digit shown (default 1, unchanged). Pair with a lower `digitCount` (e.g.
  `digitCount: 7, minStepHz: 1000`) to drop the ones/tens/hundreds-of-Hz
  digits RTL-SDR tuning never needs — they always read "0" in practice —
  leaving fewer, bigger digit cells that are easier to tap.
- Added `rtlsdr_mobile/` to this repo: a complete reference app (USB
  permission flow, tuning, WFM stereo/RDS, band scan, presets, recording
  with a foreground service, spectrum scope + waterfall) built on this
  package, with its own branding (adaptive launcher icon + native splash
  screen) — screenshots in the main README. Previously an external
  sibling project; now bundled here alongside the existing minimal
  `example/`.

## 0.3.1

- No code changes. Adds `.zenodo.json` (release archiving metadata) and
  re-tags to trigger Zenodo's GitHub integration, now enabled for this
  repo, so this and future releases are archived on Zenodo with a DOI.

## 0.3.0

- Merged the `core_rtlsdr` and `widget_rtlsdr` packages into this one.
  `driver_rtlsdr` now ships the full stack in a single dependency:
  - Layer 1 (unchanged): native USB/FFI driver — `NativeBindings`,
    `UsbChannel`/`UsbState`, `DownloadsChannel`, `DemodMode`.
  - Layer 2 (from `core_rtlsdr`): a testable radio engine —
    `RtlSdrDriver`/`NativeRtlSdrDriver`, and the `ChangeNotifier`
    controllers `RadioController`, `SpectrumController`, `RdsController`,
    `RecordingController`, `ScanController`, `PresetsController`, plus
    preset storage (`PresetsRepository`,
    `SharedPreferencesPresetsRepository`). Test doubles
    (`FakeRtlSdrDriver`, `FakeDownloadsChannel`,
    `InMemoryPresetsRepository`) are exported from
    `package:driver_rtlsdr/testing.dart`.
  - Layer 3 (from `widget_rtlsdr`): a gqrx-inspired widget library —
    `SpectrumScope`, `WaterfallView`, `SpectrumTuner`, `FrequencyReadout`,
    `SignalMeter`, `PowerReadout`, per-controller panels (`GainPanel`,
    `SquelchPanel`, `StereoRdsPanel`, `RecordingPanel`, `ScanPanel`,
    `PresetsPanel`, `StatsPanel`, `UsbStatusBanner`), theming
    (`RtlSdrTheme`/`RtlSdrThemeData`) and full screens
    (`RtlSdrImmersiveScreen`, `RtlSdrSettingsScreen`,
    `RtlSdrSettingSectionScreen`).
  - Added dependencies: `path_provider`, `shared_preferences` (dev:
    `path_provider_platform_interface`).
  - All 136 tests from the three packages now run together here; no
    breaking changes to existing `driver_rtlsdr` exports.
  - `core_rtlsdr` and `widget_rtlsdr` are no longer needed as separate
    dependencies — consumers of those packages should depend on
    `driver_rtlsdr` alone going forward.

## 0.2.1

- CI fix: `dart format` on `lib/src/downloads_channel.dart` (0.2.0 shipped
  with one un-formatted line, failing the `analyze + unit (host)` CI job's
  `dart format --set-exit-if-changed` check — the release itself, which
  doesn't run that check, was unaffected).

## 0.2.0

- Added fd-based recording: `shim_start_recording_fd`/`shim_start_iq_recording_fd`
  (native, `rtlsdr_shim.c`/`.h`) and `wav_writer_open_fd`/`iq_writer_open_fd`
  (`fdopen` instead of `fopen`, `android/src/main/cpp/dsp/`), plus
  `NativeBindings.shimStartRecordingFd`/`shimStartIqRecordingFd` — for
  writing to destinations with no plain filesystem path, like Android's
  scoped-storage-gated public Downloads folder.
- Added `DownloadsChannel`: `openDownloadsFd`/`finishDownloadsFd` (Kotlin
  `MediaStore.Downloads` insert + `ContentResolver.openFileDescriptor`,
  API 29+ only — there's no `MediaStore.Downloads` collection on older
  versions, callers should fall back to their own path-based default) and
  `shareFile` (Android's native share sheet — a `content://` URI shares
  directly, a plain path is resolved to one first via a new bundled
  `FileProvider`, since raw `file://` URIs have been blocked in share
  intents since API 24).
- New `<provider>` (`${applicationId}.driver_rtlsdr.fileprovider`) +
  `res/xml/driver_rtlsdr_file_paths.xml` in `AndroidManifest.xml`, scoped to
  the app-specific external storage `Recordings` directory this driver's
  path-based recording already writes into. No new *permission* needed for
  either the MediaStore or FileProvider paths.

## 0.1.2

- CI: fixed pub.dev auto-publish, which had silently failed for every
  release so far (0.0.2, 0.1.0, 0.1.1) — the workflow was missing the
  `dart-lang/setup-dart@v1` step that actually configures OIDC
  credentials, so `flutter pub publish` had nothing to authenticate with
  and fell back to an interactive login flow that just hangs in CI.

## 0.1.1

- Example app: mode selector now covers all 5 `DemodMode` values (added
  USB/LSB), plus PCM and raw I/Q recording controls with live
  bytes-written stats — exercises the whole new API surface manually, not
  just what `integration_test` touches.
- Validated SSB (USB/LSB) demodulation and raw I/Q recording end-to-end on
  a real RTL2838U dongle (moto g35 5G, Android 15, over Wi-Fi ADB): both
  sidebands ran without error at plausible RF/audio levels (confirmed via
  the native `dsp_thread_main` log line, not just the UI), and both a
  `.cu8` capture (byte mean ≈127.5, matching the expected offset-binary
  ADC center) and a `.wav` recording (correct mono/32kHz header, valid
  RIFF size fixup) were pulled off the device and inspected. First time
  either recording path or SSB has run against real hardware rather than
  just the emulator/synthetic tests.

## 0.1.0

- Added a component-by-component reference doc (`docs/index.html`) for the
  native C/C++ core and its Dart bindings.
- Added SSB demodulation (`DemodMode.usb`/`.lsb`), phasing method — Hilbert
  transform on Q with a matched delay on I, so the unwanted sideband is
  actually rejected (`android/src/main/cpp/dsp/demod_ssb.c`). Squelch now
  applies to USB/LSB too (only WFM doesn't squelch). Verified against a
  synthetic single-tone signal in `tool/native_tests/test_demod_ssb.c`
  (host-only, no hardware/emulator needed — see that file for how to run
  it), since there's no existing native DSP test harness in this repo.
- Added raw I/Q recording (`shimStartIqRecording`/`shimStopIqRecording`),
  independent of the existing demodulated-PCM recording — dumps the
  interleaved 8-bit unsigned I/Q exactly as the dongle sends it, tapped
  before decimation/demodulation (`android/src/main/cpp/dsp/iq_writer.c`),
  in the same `.cu8` format `rtl_sdr`/GNU Radio/gqrx use for raw captures.
  New `ShimStats.iqRecordingBytesWritten` field (`shim_stats_t` grew from
  40 to 48 bytes — see the updated FFI layout test).

## 0.0.2

- Translated the entire codebase (comments, docs, log/error messages) from
  Portuguese to English in preparation for open-sourcing the project.
- Added CI (`flutter analyze`/`flutter test` for the plugin and example
  app, plus a full native Android build) and a tag-triggered release
  workflow that publishes a zipped, versioned build and auto-publishes to
  pub.dev.
- Added `CONTRIBUTING.md` and expanded Dart unit test coverage
  (`UsbState`/`UsbDeviceInfo`, `NativeLibrary`).

## 0.0.1

- Initial extraction of the native driver (USB, tuning, streaming,
  WFM/NFM/AM demodulation with stereo and RDS, spectrum, recording,
  gain/squelch) from the `rtl-sdr mobile` app as a reusable Flutter Android
  plugin.
- Native core (C, GPLv2) identical to the source app — see
  `../rtl-sdr mobile/docs/how-it-was-built.md` for how it was designed and
  validated against real hardware.
- Public Dart API: `UsbState`/`UsbChannel` (USB permission/attach),
  `NativeBindings` (direct FFI to `rtlsdr_shim.h`), `DemodMode`,
  `ShimStats`, `ShimRdsInfo`.
- `example/` with a minimal working app (permission → tuning → streaming →
  live statistics).
