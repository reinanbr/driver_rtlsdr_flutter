import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DemodMode', () {
    test('nativeValue espelha demod_mode_t de rtlsdr_shim.h', () {
      // Estes valores são passados direto pra shim_set_demod_mode via FFI —
      // mudar sem atualizar o C (ou vice-versa) quebra silenciosamente.
      expect(DemodMode.wfm.nativeValue, 0);
      expect(DemodMode.nfm.nativeValue, 1);
      expect(DemodMode.am.nativeValue, 2);
    });

    test('fromNativeValue faz o round-trip de cada modo', () {
      for (final mode in DemodMode.values) {
        expect(DemodMode.fromNativeValue(mode.nativeValue), mode);
      }
    });

    test('fromNativeValue cai pra WFM num valor desconhecido', () {
      expect(DemodMode.fromNativeValue(99), DemodMode.wfm);
    });

    test('só NFM/AM suportam squelch — WFM (rádio comercial) não', () {
      expect(DemodMode.wfm.supportsSquelch, isFalse);
      expect(DemodMode.nfm.supportsSquelch, isTrue);
      expect(DemodMode.am.supportsSquelch, isTrue);
    });
  });
}
