import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:driver_rtlsdr/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [FakeRtlSdrDriver.gainList] ships the tenths-of-a-dB gain steps a real
/// RTL2832U + R820T2 tuner reports (see driver_rtlsdr's native gain query)
/// — exercising [GainPanel] against it verifies the widget matches what
/// `RtlSdrDriver.getGainList()` actually returns on Android hardware.
void main() {
  testWidgets('AGC on by default, no manual slider shown', (tester) async {
    final radio = RadioController(FakeRtlSdrDriver());
    addTearDown(radio.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GainPanel(radio: radio)),
      ),
    );

    expect(radio.gainAuto, isTrue);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('switching off AGC without a gain list shows guidance text', (
    tester,
  ) async {
    final radio = RadioController(FakeRtlSdrDriver());
    addTearDown(radio.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GainPanel(radio: radio)),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(radio.gainAuto, isFalse);
    expect(find.byType(Slider), findsNothing);
    expect(find.textContaining('refreshGainList'), findsOneWidget);
  });

  testWidgets('manual gain slider drives RadioController.gainTenthDb', (
    tester,
  ) async {
    final radio = RadioController(FakeRtlSdrDriver())..refreshGainList();
    addTearDown(radio.dispose);
    radio.setGainAuto(false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GainPanel(radio: radio)),
      ),
    );

    expect(find.byType(Slider), findsOneWidget);

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(slider.max);
    expect(radio.gainTenthDb, radio.gainList.last);
  });
}
