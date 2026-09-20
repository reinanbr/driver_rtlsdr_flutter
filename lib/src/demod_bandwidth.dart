import 'package:driver_rtlsdr/driver_rtlsdr.dart';

/// Typical channel bandwidth (Hz) for [mode] — used to draw the passband/
/// filter overlay on [SpectrumScope]/[WaterfallView], the same "shaded
/// band around the tuned frequency" gqrx and CubicSDR both show. These are
/// broadcast-channel-spacing defaults (commercial WFM: 200 kHz per the US
/// FCC mask; NFM: 12.5 kHz narrowband land-mobile spacing; AM: 10 kHz US
/// broadcast spacing; USB/LSB: 2.7 kHz, the usual ham-radio SSB voice
/// filter width) meant to look right out of the box — pass an explicit
/// `passbandHz` to either widget instead if an app needs the receiver's
/// actual filter width.
int defaultPassbandHzFor(DemodMode mode) => switch (mode) {
  DemodMode.wfm => 200000,
  DemodMode.nfm => 12500,
  DemodMode.am => 10000,
  DemodMode.usb || DemodMode.lsb => 2700,
};
