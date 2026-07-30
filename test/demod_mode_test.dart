import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DemodMode', () {
    test('nativeValue mirrors demod_mode_t from rtlsdr_shim.h', () {
      // These values are passed directly to shim_set_demod_mode via FFI —
      // changing them without updating the C side (or vice versa) breaks silently.
      expect(DemodMode.wfm.nativeValue, 0);
      expect(DemodMode.nfm.nativeValue, 1);
      expect(DemodMode.am.nativeValue, 2);
      expect(DemodMode.usb.nativeValue, 3);
      expect(DemodMode.lsb.nativeValue, 4);
    });

    test('fromNativeValue round-trips each mode', () {
      for (final mode in DemodMode.values) {
        expect(DemodMode.fromNativeValue(mode.nativeValue), mode);
      }
    });

    test('fromNativeValue falls back to WFM on an unknown value', () {
      expect(DemodMode.fromNativeValue(99), DemodMode.wfm);
    });

    test(
      'only NFM/AM/USB/LSB support squelch — WFM (commercial broadcast) does not',
      () {
        expect(DemodMode.wfm.supportsSquelch, isFalse);
        expect(DemodMode.nfm.supportsSquelch, isTrue);
        expect(DemodMode.am.supportsSquelch, isTrue);
        expect(DemodMode.usb.supportsSquelch, isTrue);
        expect(DemodMode.lsb.supportsSquelch, isTrue);
      },
    );

    test('only WFM supports stereo/RDS', () {
      expect(DemodMode.wfm.supportsStereoAndRds, isTrue);
      expect(DemodMode.nfm.supportsStereoAndRds, isFalse);
      expect(DemodMode.am.supportsStereoAndRds, isFalse);
      expect(DemodMode.usb.supportsStereoAndRds, isFalse);
      expect(DemodMode.lsb.supportsStereoAndRds, isFalse);
    });
  });
}
