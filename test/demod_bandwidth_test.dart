import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter_test/flutter_test.dart';

/// [DemodMode] (driver_rtlsdr's Android-side demod enum) drives which
/// passband width [SpectrumScope]/[WaterfallView] shade — narrower modes
/// must map to narrower bands.
void main() {
  test('wfm has the widest default passband, am the narrowest', () {
    expect(
      defaultPassbandHzFor(DemodMode.wfm),
      greaterThan(defaultPassbandHzFor(DemodMode.nfm)),
    );
    expect(
      defaultPassbandHzFor(DemodMode.nfm),
      greaterThan(defaultPassbandHzFor(DemodMode.am)),
    );
  });

  test('every mode has a positive bandwidth', () {
    for (final mode in DemodMode.values) {
      expect(defaultPassbandHzFor(mode), greaterThan(0));
    }
  });
}
