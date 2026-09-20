/// Frequency↔pixel-fraction conversions shared by `SpectrumScope` and
/// `SpectrumTuner` — both lay the spectrum out the same way: `spanHz` wide,
/// centered on `centerFrequencyHz`, fraction `0.0` at the left edge and
/// `1.0` at the right edge.
library;

/// The frequency (Hz) at horizontal position [fraction] (0..1, left to
/// right) across a plot spanning [spanHz] centered on [centerFrequencyHz].
int frequencyAtFraction({
  required int centerFrequencyHz,
  required int spanHz,
  required double fraction,
}) {
  final clamped = fraction.clamp(0.0, 1.0);
  final startHz = centerFrequencyHz - spanHz ~/ 2;
  return startHz + (clamped * spanHz).round();
}

/// The inverse of [frequencyAtFraction]: the horizontal fraction (0..1,
/// unclamped) at which [frequencyHz] falls across a plot spanning [spanHz]
/// centered on [centerFrequencyHz].
double fractionForFrequency({
  required int centerFrequencyHz,
  required int spanHz,
  required int frequencyHz,
}) {
  if (spanHz == 0) return 0.5;
  final startHz = centerFrequencyHz - spanHz ~/ 2;
  return (frequencyHz - startHz) / spanHz;
}
