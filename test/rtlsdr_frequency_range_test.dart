import 'package:flutter_test/flutter_test.dart';
import 'package:driver_rtlsdr/driver_rtlsdr.dart';

void main() {
  test('bounds match the R820T/R820T2 tuning range', () {
    expect(RtlSdrFrequencyRange.minHz, 24000000);
    expect(RtlSdrFrequencyRange.maxHz, 1766000000);
  });

  test('clamp leaves in-range values untouched', () {
    expect(RtlSdrFrequencyRange.clamp(100000000), 100000000);
  });

  test('clamp pulls low values up to minHz', () {
    expect(RtlSdrFrequencyRange.clamp(0), RtlSdrFrequencyRange.minHz);
  });

  test('clamp pulls high values down to maxHz', () {
    expect(RtlSdrFrequencyRange.clamp(3000000000), RtlSdrFrequencyRange.maxHz);
  });
}
