import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:driver_rtlsdr/driver_rtlsdr.dart';

void main() {
  testWidgets('formats the value to the given decimals with its unit', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PowerReadout(valueDb: -42.34))),
    );

    expect(find.text('-42.3 dBFS'), findsOneWidget);
  });

  testWidgets('supports a custom unit and decimal count', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PowerReadout(valueDb: -13.0, unit: 'dBm', decimals: 0),
        ),
      ),
    );

    expect(find.text('-13 dBm'), findsOneWidget);
  });
}
