# driver_rtlsdr

[![pub package](https://img.shields.io/pub/v/driver_rtlsdr.svg)](https://pub.dev/packages/driver_rtlsdr)
[![pub points](https://img.shields.io/pub/points/driver_rtlsdr)](https://pub.dev/packages/driver_rtlsdr/score)
[![pub likes](https://img.shields.io/pub/likes/driver_rtlsdr)](https://pub.dev/packages/driver_rtlsdr/score)
[![CI](https://github.com/reinanbr/driver_rtlsdr_flutter/actions/workflows/ci.yml/badge.svg)](https://github.com/reinanbr/driver_rtlsdr_flutter/actions/workflows/ci.yml)
[![License: GPL v2 or later](https://img.shields.io/badge/license-GPLv2--or--later-blue.svg)](LICENSE)

Android driver (Flutter plugin) for RTL-SDR dongles (RTL2832U chipset) over
USB-OTG. Extracted from the [`rtl-sdr mobile`](../rtl-sdr%20mobile) app
(sibling folder to this package) so that other Flutter software-defined-radio
apps can build their own UI/UX on top of the same native core, instead of
reimplementing USB + libusb + librtlsdr + DSP from scratch.

The native core (C, `android/src/main/cpp/`) is **identical** to the one in
the source app — same pipeline: USB permission/open → raw IQ streaming →
two-stage decimation → demodulation (WFM/NFM/AM, with stereo and RDS on WFM)
→ PCM to the speaker (Oboe), with WAV recording and spectrum readout for
waterfall/visualization.

## What this package provides

- **USB**: dongle detection, permission flow (`UsbState`/`UsbChannel`,
  `MethodChannel`/`EventChannel` over `DriverRtlsdrPlugin.kt`).
- **Tuning**: frequency, sample rate.
- **Demodulation**: WFM (with stereo and RDS), NFM, AM (`DemodMode`).
- **WFM stereo**: 19kHz pilot PLL, live on/off toggle
  (`shimSetStereoEnabled`), lock reported in `ShimStats.stereoLocked`.
- **RDS**: PI/PTY/TP/TA/PS/RadioText (`ShimRdsInfo`, via `shimGetRdsInfo`),
  live on/off toggle (`shimSetRdsEnabled`).
- **Gain**: automatic (AGC) or manual, list of gains supported by the
  tuner.
- **Squelch**: NFM/AM (WFM doesn't use it — a commercial radio wouldn't have
  squelch).
- **Spectrum**: dB snapshot of the whole captured band, ready to plot
  (`shimGetSpectrumDb`).
- **Recording**: records the demodulated PCM (mono or stereo, whatever the
  session is producing) directly to a WAV file (`shimStartRecording`/
  `shimStopRecording`).
- **Statistics**: IQ rate, ring buffer overflow, RF/audio level
  (`ShimStats`, via `shimGetStats`).

## What this package deliberately does NOT provide

- **UI**: zero widgets. The consuming app builds the interface.
- **Foreground service**: keeping the process alive in the background during
  streaming is a UX decision for each app — it isn't bundled here. A
  consuming app that needs this can implement its own (see
  `StreamingService.kt` in the `rtl-sdr mobile` app as a reference).
- **Where to save recordings**: `shimStartRecording` takes an absolute
  path — the app chooses it (typically via `path_provider`).
- **Presets, automatic scanning, visual carousel/tuner**: these are
  application logic built on top of this driver's API, not part of it. The
  `rtl-sdr mobile` app has reference implementations of all of this
  (`lib/radio/scan_controller.dart`, `lib/widgets/spectrum_tuner.dart`,
  etc.) that can be adapted.

## Installation

```yaml
dependencies:
  driver_rtlsdr:
    path: ../driver_rtlsdr # or a git/pub reference, if published
```

## Integrating into a new app

1. **`AndroidManifest.xml`** of your app — add the auto-open intent filter
   for when the dongle is plugged in (optional, but it's what makes Android
   offer to open your app when the user connects the dongle) and point the
   `meta-data` to the VID/PID filter already included in this package:

   ```xml
   <activity ...>
       <intent-filter>
           <action android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED" />
       </intent-filter>
       <meta-data
           android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED"
           android:resource="@xml/device_filter" />
   </activity>
   ```

   `@xml/device_filter` resolves to `driver_rtlsdr`'s own resource (merged
   into the build by Gradle's resource merger — no need to copy anything).
   `android.hardware.usb.host` is already declared by the plugin's manifest
   and is also merged automatically.

2. **`minSdk = 26`** — required by the Oboe/AAudio low-latency path used
   internally for audio output.

3. **Lifecycle**: `UsbState` + `UsbChannel` (call
   `refreshConnectedDevices()` when your screen starts — this covers the
   case where the dongle is already plugged in when the app opens) →
   `requestPermission()` → listen for the `deviceReady` event → from there,
   `NativeBindings.shim*` are free to use (`shimSetFrequencyHz`,
   `shimSetDemodMode`, `shimStartStreaming`, etc.).

4. See `example/` in this package for a minimal, fully working
   implementation (permission → tuning via slider → mode selection →
   start/stop streaming → live statistics, including stereo pilot lock).

## Tests

- `test/` — pure Dart unit tests, run on the host (no Android or dongle
  needed): `DemodMode` (native values, round-trip, squelch) and the
  **byte size of the FFI structs** (`ShimStats`/`ShimRdsInfo`) against the
  expected layout computed from `rtlsdr_shim.h` — catches the most common
  mistake when evolving the native API (forgetting to mirror a new field on
  both sides). Run with: `flutter test`.
- `example/integration_test/` — runs on a real Android device/emulator;
  confirms that `libnative_rtlsdr.so` builds, links, and loads on that
  specific ABI, and that a real FFI call works — without needing a dongle
  physically connected. Run with:
  `cd example && flutter test integration_test`.
- **Validation against real hardware**: this package's native core is
  byte-for-byte the same as the `rtl-sdr mobile` app, which was tested live
  against a real RTL2838U dongle (USB permission, tuning, streaming, mode
  switching, stereo pilot lock, RDS sync/decoding against a real station,
  recording, scanning) — see
  `../rtl-sdr mobile/docs/how-it-was-built.md` for the full results of that
  validation. **This package's example app specifically** had its native
  build validated (compiled and linked cleanly from scratch, all
  vendored/adapted sources building correctly) and was successfully
  installed on a real device; the live visual smoke test (opening the
  screen, requesting permission, tuning) was left pending because the test
  device's battery ran out (5%) mid-session — not an app failure. This is
  the recommended first validation step before publishing/depending on this
  package in production.

## License

GPLv2, or (at your option) any later version — see [`LICENSE`](LICENSE).
This driver links `librtlsdr` (GPLv2-or-later), which requires that any app
using it be distributed under the GPL. `libusb` (LGPL-2.1) and KissFFT
(BSD-3-Clause) are vendored under `android/src/main/cpp/vendor/`; Oboe
(Apache-2.0) is a Gradle/Prefab dependency. See `LICENSE` for the full
breakdown.

## Architecture / how the native driver works

See [`../rtl-sdr mobile/docs/how-it-was-built.md`](../rtl-sdr%20mobile/docs/how-it-was-built.md)
(and its translation [`como-foi-construido.md`](../rtl-sdr%20mobile/docs/como-foi-construido.md))
for a detailed technical explanation of how stereo/RDS decoding, automatic
scanning, recording, and the visual tuner were designed and validated — that
document describes the same native core this package exposes as a plugin.

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for how to
set up your environment, coding conventions, and the PR process.
