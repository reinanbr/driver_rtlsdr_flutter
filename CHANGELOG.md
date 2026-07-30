## Unreleased

- Added SSB demodulation (`DemodMode.usb`/`.lsb`), phasing method — Hilbert
  transform on Q with a matched delay on I, so the unwanted sideband is
  actually rejected (`android/src/main/cpp/dsp/demod_ssb.c`). Squelch now
  applies to USB/LSB too (only WFM doesn't squelch). Verified against a
  synthetic single-tone signal in `tool/native_tests/test_demod_ssb.c`
  (host-only, no hardware/emulator needed — see that file for how to run
  it), since there's no existing native DSP test harness in this repo.

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
