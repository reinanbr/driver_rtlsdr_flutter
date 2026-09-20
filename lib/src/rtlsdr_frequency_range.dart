/// Tuning range (Hz) of the RTL-SDR dongles this library targets: the
/// Rafael Micro R820T/R820T2 tuner paired with the RTL2832U — by far the
/// most common combination in retail RTL-SDR dongles today, and the tuner
/// `driver_rtlsdr`'s vendored `librtlsdr` drives by default. Its PLL only
/// locks between roughly 24 MHz and 1766 MHz; ask it for a frequency
/// outside that band and it just fails to lock (or silently aliases),
/// there's no native error surfaced for "out of range".
///
/// Neither `driver_rtlsdr` nor `core_rtlsdr` enforce this themselves —
/// `RadioController.setFrequencyHz` forwards whatever it's given straight
/// to the native tuner — so this widget layer is what keeps the tuning UI
/// ([FrequencyReadout], [SpectrumTuner], [SpectrumScope]) from ever asking
/// for a frequency the hardware can't actually tune to. A host app driving
/// a different tuner chip (e.g. an E4000-based dongle) can override these
/// bounds by passing its own `minHz`/`maxHz` (or `minFrequencyHz`/
/// `maxFrequencyHz`) to those widgets instead.
abstract final class RtlSdrFrequencyRange {
  /// Lowest frequency (Hz) the R820T/R820T2 PLL can lock to (~24.0 MHz).
  static const int minHz = 24000000;

  /// Highest frequency (Hz) the R820T/R820T2 PLL can lock to (~1766.0 MHz).
  static const int maxHz = 1766000000;

  /// Clamps [frequencyHz] into [minHz]..[maxHz].
  static int clamp(int frequencyHz) => frequencyHz.clamp(minHz, maxHz);
}
