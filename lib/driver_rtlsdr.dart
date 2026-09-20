/// End-to-end RTL-SDR (RTL2832U) stack for Flutter/Android, merged from three
/// previously separate packages (`driver_rtlsdr`, `core_rtlsdr`,
/// `widget_rtlsdr`) into this one: native USB/FFI driver, a testable radio
/// engine, and a gqrx-inspired widget library, all in a single dependency.
///
/// ## Layer 1 — native driver (no UI, no session logic)
///
/// Extracted from the `rtl-sdr mobile` app as a reusable plugin — the native
/// core (C, GPLv2, see `android/src/main/cpp/`) exposes tuning, IQ streaming,
/// demodulation, gain, squelch, stereo, RDS, spectrum and recording as raw
/// FFI/USB primitives with no opinion on session logic or UI:
///
/// 1. [UsbState] + [UsbChannel]: detects the dongle, requests permission,
///    listens for the `deviceReady` event (only then is the native driver
///    open and ready).
/// 2. [NativeBindings]: tuning (`shimSetFrequencyHz`), demodulation mode
///    ([DemodMode] — WFM/NFM/AM), gain, squelch, stereo, RDS, streaming
///    (`shimStartStreaming`/`shimStopStreaming`), statistics ([ShimStats],
///    via `shimGetStats`), RDS ([ShimRdsInfo], via `shimGetRdsInfo`),
///    spectrum (`shimGetSpectrumDb`) and recording (`shimStartRecording`).
/// 3. Storage: a plain absolute path (`shim_start_recording`, typically via
///    `path_provider`) or the public Downloads folder via MediaStore
///    ([DownloadsChannel.openDownloadsFd] + `shim_start_recording_fd`).
///
/// It has no UI and doesn't manage a foreground service — that remains a
/// decision for the consuming app.
///
/// ## Layer 2 — radio engine
///
/// [RtlSdrDriver] gives every piece of native state (tuning, streaming,
/// gain, stats, RDS, spectrum, recording) a plain-Dart shape, and a set of
/// `ChangeNotifier` controllers — [RadioController], [SpectrumController],
/// [RdsController], [RecordingController], [ScanController],
/// [PresetsController] — turn that into ready-to-use radio behavior,
/// unit-testable on a host with no dongle or emulator (see
/// `package:driver_rtlsdr/testing.dart`'s [FakeRtlSdrDriver]).
///
/// ## Layer 3 — widgets
///
/// A gqrx-inspired widget library built entirely on the controllers above:
/// [FrequencyReadout] (odometer-style digit tuner), [SpectrumScope] (FFT
/// line/fill plot), [WaterfallView] (scrolling spectrogram), [SpectrumTuner]
/// (combined scope + waterfall), [SignalMeter], [PowerReadout]; control
/// panels [GainPanel], [SquelchPanel], [StereoRdsPanel], [RecordingPanel],
/// [ScanPanel], [PresetsPanel], [StatsPanel], [UsbStatusBanner] (each a
/// self-contained [RtlSdrPanel] section); theming via [RtlSdrTheme] /
/// [RtlSdrThemeData]; and full screens ([RtlSdrImmersiveScreen],
/// [RtlSdrSettingsScreen], [RtlSdrSettingSectionScreen]) built from
/// [RtlSdrSettingsSection] entries that can be distributed three ways
/// (immersive settings button, wide-screen side panel, or a host app's own
/// navigation) without touching the panels themselves.
///
/// See README.md for integration details (manifest, permissions) and
/// `example/` for a minimal, fully working app exercising the whole stack.
library;

// Layer 1 — native driver.
export 'src/demod_mode.dart';
export 'src/downloads_channel.dart';
export 'src/native_bindings.dart';
export 'src/native_library.dart';
export 'src/shim_types.dart';
export 'src/usb_channel.dart';
export 'src/usb_state.dart';

// Layer 2 — radio engine (controllers, driver abstraction, presets storage).
export 'src/controllers/presets_controller.dart';
export 'src/controllers/radio_controller.dart';
export 'src/controllers/rds_controller.dart';
export 'src/controllers/recording_controller.dart';
export 'src/controllers/scan_controller.dart';
export 'src/controllers/spectrum_controller.dart';
export 'src/driver/native_rtlsdr_driver.dart';
export 'src/driver/rtlsdr_driver.dart';
export 'src/storage/in_memory_presets_repository.dart';
export 'src/storage/preset.dart';
export 'src/storage/presets_repository.dart';
export 'src/storage/shared_preferences_presets_repository.dart';

// Layer 3 — widgets, panels, screens, theming.
export 'src/demod_bandwidth.dart';
export 'src/navigation/rtlsdr_settings_section.dart';
export 'src/rtlsdr_frequency_range.dart';
export 'src/panels/gain_panel.dart';
export 'src/panels/presets_panel.dart';
export 'src/panels/recording_panel.dart';
export 'src/panels/scan_panel.dart';
export 'src/panels/squelch_panel.dart';
export 'src/panels/stats_panel.dart';
export 'src/panels/stereo_rds_panel.dart';
export 'src/panels/usb_status_banner.dart';
export 'src/screens/rtlsdr_immersive_screen.dart';
export 'src/screens/rtlsdr_setting_section_screen.dart';
export 'src/screens/rtlsdr_settings_screen.dart';
export 'src/theme/rtlsdr_theme.dart';
export 'src/theme/rtlsdr_theme_data.dart';
export 'src/widgets/frequency_readout.dart';
export 'src/widgets/mode_selector.dart';
export 'src/widgets/power_readout.dart';
export 'src/widgets/rtlsdr_panel.dart';
export 'src/widgets/signal_meter.dart';
export 'src/widgets/spectrum_scope.dart';
export 'src/widgets/spectrum_tuner.dart';
export 'src/widgets/waterfall_view.dart';
