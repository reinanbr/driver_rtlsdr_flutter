import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rtlsdr_mobile/app.dart';

void main() {
  testWidgets('App builds and shows the device screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const RtlSdrApp());
    await tester.pump();

    expect(find.text('RTL-SDR Mobile'), findsOneWidget);
    expect(find.byIcon(Icons.usb_off), findsOneWidget);
  });
}
