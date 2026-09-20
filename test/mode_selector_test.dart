import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:driver_rtlsdr/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [DemodMode] is driver_rtlsdr's Android-side demodulation enum (WFM/NFM/
/// AM/USB/LSB, applied through `RtlSdrDriver.setDemodMode` on the native
/// DSP thread) — [ModeSelector] just needs [RadioController] to exercise
/// every mode without touching FFI, via [FakeRtlSdrDriver].
void main() {
  testWidgets('shows every DemodMode.values entry, WFM selected by default', (
    tester,
  ) async {
    final radio = RadioController(FakeRtlSdrDriver());
    addTearDown(radio.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ModeSelector(radio: radio)),
      ),
    );

    // ModeSelector iterates DemodMode.values rather than a hardcoded list,
    // so it stays correct as driver_rtlsdr adds modes (e.g. USB/LSB SSB).
    for (final mode in DemodMode.values) {
      expect(find.text(mode.shortLabel), findsOneWidget);
    }
    expect(radio.demodMode, DemodMode.wfm);
  });

  testWidgets('tapping a segment switches RadioController.demodMode', (
    tester,
  ) async {
    final radio = RadioController(FakeRtlSdrDriver());
    addTearDown(radio.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ModeSelector(radio: radio)),
      ),
    );

    await tester.tap(find.text('NFM'));
    await tester.pumpAndSettle();

    expect(radio.demodMode, DemodMode.nfm);
    expect(radio.demodMode.supportsSquelch, isTrue);
  });
}
