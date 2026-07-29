# Contributing to driver_rtlsdr

Thanks for considering a contribution! This document covers how to set up
your environment, the conventions this project follows, and how to submit
changes.

## Project layout

- `lib/` — public Dart API (USB permission/attach, FFI bindings, types).
- `android/src/main/kotlin/` — Kotlin glue (`UsbManager`, permission flow,
  JNI bridge into the native library).
- `android/src/main/cpp/` — native core (C, GPLv2): USB streaming, DSP
  pipeline (decimation, demodulation, stereo, RDS, spectrum, recording).
- `android/src/main/cpp/vendor/` — third-party vendored sources (libusb,
  librtlsdr, KissFFT). Don't hand-edit these; see
  [tool/setup_native_deps.sh](tool/setup_native_deps.sh).
- `example/` — minimal Flutter app exercising the plugin's public API.
- `test/` — pure Dart unit tests (host-only, no Android/dongle required).
- `example/integration_test/` — on-device test that the native library
  builds, links and loads on a real Android ABI.

See [README.md](README.md) for the architecture overview and what the
driver deliberately does and does not provide.

## Getting set up

You'll need:

- Flutter (stable channel) — see `environment.sdk`/`flutter` in
  [pubspec.yaml](pubspec.yaml) for the minimum versions.
- Android SDK with NDK `28.2.13676358` and CMake `3.22.1` (the exact
  versions pinned in [android/build.gradle.kts](android/build.gradle.kts)).
- A JDK 17.

```bash
flutter pub get
cd example && flutter pub get
```

If you ever need to re-vendor `libusb`/`librtlsdr`/`KissFFT` (e.g. to bump
a version), use [tool/setup_native_deps.sh](tool/setup_native_deps.sh)
rather than editing `android/src/main/cpp/vendor/` by hand.

## Building the example app

```bash
cd example
flutter build apk --debug
```

If the very first native build fails with strange C++ standard library
errors (e.g. `redefinition of 'sigaction'`), see the comments at the top
of [android/src/main/cpp/CMakeLists.txt](android/src/main/cpp/CMakeLists.txt)
and [tool/cxx_env_wrapper.sh](tool/cxx_env_wrapper.sh) — this is caused by
a polluted environment from Flutter's snap packaging on some Linux setups
and only affects the very first configure.

## Running tests

```bash
flutter test                              # plugin unit tests (host, no device needed)
cd example && flutter test                # example app widget tests
cd example && flutter test integration_test  # on a real device/emulator
```

CI (`.github/workflows/ci.yml`) runs `dart format --set-exit-if-changed`,
`flutter analyze`, and `flutter test` for both the plugin and the example
app, plus a full native Android build to catch native-core regressions.
Please make sure all of this passes locally before opening a PR.

## Coding conventions

- **Dart**: follow `flutter_lints` (see
  [analysis_options.yaml](analysis_options.yaml)); run `dart format .`
  before committing.
- **Kotlin**: match the existing style in
  `android/src/main/kotlin/` (no linter enforced, but keep it consistent).
- **C**: match the existing style in `android/src/main/cpp/` — no
  trailing whitespace, braces on the same line, comments in English.
  Only comment the *why* (non-obvious constraints, tradeoffs, hardware
  quirks), not the *what*.
- Don't hand-edit vendored code under `android/src/main/cpp/vendor/`.
- No hardware-in-the-loop validation is currently available in this
  project's development environment (no RTL-SDR dongle attached to CI or
  to most contributors' machines) — several DSP components (stereo PLL,
  RDS decoder) ship with loop gains and thresholds that are *estimates*,
  documented as such in code comments. If you have access to real
  hardware and can validate/tune these, that is an especially valuable
  contribution — please describe what you tested in your PR.

## Submitting changes

1. Fork the repository and create a branch from `main`.
2. Keep changes focused — prefer several small PRs over one large one.
3. Add or update tests for behavior changes where feasible.
4. Update [CHANGELOG.md](CHANGELOG.md) under an `## Unreleased` section
   (create one if it doesn't exist) describing user-visible changes.
5. Open a pull request describing what changed and why, and what you
   tested (host tests, example app build, real hardware if available).

## Reporting bugs / requesting features

Please open a GitHub issue with:

- What you expected vs. what happened.
- Flutter/Dart version (`flutter --version`), Android version, and dongle
  model, if relevant.
- Logs (`adb logcat` filtered to the `rtlsdr_shim` / `DriverRtlsdrPlugin`
  tags) for native-side issues.

## License

By contributing, you agree that your contributions will be licensed under
the same terms as the project — GPLv2, or (at your option) any later
version. See [LICENSE](LICENSE).
