/// Android driver for RTL-SDR (RTL2832U) dongles via USB-OTG.
///
/// Extracted from the `rtl-sdr mobile` app (sibling folder of this package) as a
/// reusable Flutter plugin — the native core (C, GPLv2, see
/// `android/src/main/cpp/`) doesn't change between this package and the original
/// app; what changes is that here it's exposed as a public API for any
/// software-defined-radio Flutter app to build its own UI on
/// top of, instead of being embedded inside one specific app.
///
/// ## What this package does NOT do
///
/// By design, to keep the driver focused: it has no UI, doesn't manage a
/// foreground service (keeping the process alive with the app in the background
/// during streaming — that's a UX decision for each consuming app), and doesn't
/// decide where to save recordings (`shim_start_recording` receives an
/// absolute path — the app chooses where, typically via `path_provider`).
///
/// ## How to build an app on top of it
///
/// 1. [UsbState] + [UsbChannel]: detects the dongle, requests permission, listens for the
///    `deviceReady` event (only then is the native driver open and ready).
/// 2. [NativeBindings]: tuning (`shimSetFrequencyHz`), demodulation mode
///    ([DemodMode] — WFM/NFM/AM), gain, squelch, stereo, RDS, streaming
///    (`shimStartStreaming`/`shimStopStreaming`), statistics ([ShimStats],
///    via `shimGetStats`), RDS ([ShimRdsInfo], via `shimGetRdsInfo`),
///    spectrum (`shimGetSpectrumDb`) and recording (`shimStartRecording`).
/// 3. The app builds its own controllers (`ChangeNotifier` + periodic
///    polling is the pattern used in the reference app) on top of these
///    calls — see `example/` in this package for a minimal working
///    implementation, and the `rtl-sdr mobile` app (sibling of this package) for a
///    complete implementation (stereo, RDS, automatic scan, recording,
///    visual spectrum-based tuner).
///
/// See README.md for integration details (manifest, permissions) and
/// `docs/` in the `rtl-sdr mobile` app for how the native driver itself was
/// designed (stereo pilot PLL, RDS decoder, etc).
library;

export 'src/demod_mode.dart';
export 'src/native_bindings.dart';
export 'src/native_library.dart';
export 'src/shim_types.dart';
export 'src/usb_channel.dart';
export 'src/usb_state.dart';
