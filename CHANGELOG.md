## Unreleased

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
