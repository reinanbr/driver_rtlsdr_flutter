import 'package:flutter_test/flutter_test.dart';
import 'package:driver_rtlsdr/src/spectrum_geometry.dart';

void main() {
  test('frequencyAtFraction: 0.5 is the center frequency', () {
    expect(
      frequencyAtFraction(
        centerFrequencyHz: 100000000,
        spanHz: 1000000,
        fraction: 0.5,
      ),
      100000000,
    );
  });

  test('frequencyAtFraction: 0.0/1.0 are the span edges', () {
    expect(
      frequencyAtFraction(
        centerFrequencyHz: 100000000,
        spanHz: 1000000,
        fraction: 0.0,
      ),
      99500000,
    );
    expect(
      frequencyAtFraction(
        centerFrequencyHz: 100000000,
        spanHz: 1000000,
        fraction: 1.0,
      ),
      100500000,
    );
  });

  test('frequencyAtFraction clamps fraction to 0..1', () {
    expect(
      frequencyAtFraction(
        centerFrequencyHz: 100000000,
        spanHz: 1000000,
        fraction: -3,
      ),
      99500000,
    );
    expect(
      frequencyAtFraction(
        centerFrequencyHz: 100000000,
        spanHz: 1000000,
        fraction: 3,
      ),
      100500000,
    );
  });

  test('fractionForFrequency is the inverse of frequencyAtFraction', () {
    const center = 100000000;
    const span = 1000000;
    for (final fraction in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      final freq = frequencyAtFraction(
        centerFrequencyHz: center,
        spanHz: span,
        fraction: fraction,
      );
      expect(
        fractionForFrequency(
          centerFrequencyHz: center,
          spanHz: span,
          frequencyHz: freq,
        ),
        closeTo(fraction, 1e-9),
      );
    }
  });
}
