import 'package:flutter_test/flutter_test.dart';
import 'package:driver_rtlsdr/src/painters/spectrum_painter.dart';
import 'package:driver_rtlsdr/driver_rtlsdr.dart';

void main() {
  final theme = RtlSdrThemeData.dark();

  test('shouldRepaint is true when the tuned frequency or span changes', () {
    final a = SpectrumPainter(
      bins: const [-80, -70, -60],
      minDb: -100,
      maxDb: 0,
      theme: theme,
      centerFrequencyHz: 100000000,
      spanHz: 1000000,
    );
    final b = SpectrumPainter(
      bins: const [-80, -70, -60],
      minDb: -100,
      maxDb: 0,
      theme: theme,
      centerFrequencyHz: 101000000,
      spanHz: 1000000,
    );

    expect(a.shouldRepaint(b), isTrue);
  });

  test('shouldRepaint is false for an identical configuration', () {
    const bins = [-80.0, -70.0, -60.0];
    final a = SpectrumPainter(
      bins: bins,
      minDb: -100,
      maxDb: 0,
      theme: theme,
      centerFrequencyHz: 100000000,
      spanHz: 1000000,
      passbandHz: 200000,
      cursorFraction: 0.5,
    );
    final b = SpectrumPainter(
      bins: bins,
      minDb: -100,
      maxDb: 0,
      theme: theme,
      centerFrequencyHz: 100000000,
      spanHz: 1000000,
      passbandHz: 200000,
      cursorFraction: 0.5,
    );

    expect(a.shouldRepaint(b), isFalse);
  });
}
