// Basic widget test for the example app — runs on the host, without
// Android/a dongle: it only verifies that the UI mounts and shows the
// initial "no device" state, without attempting any real FFI call
// (NativeBindings is only touched from _TunerDemo, which only appears once
// the USB status becomes deviceReady — impossible to simulate without a
// real MethodChannel/EventChannel implementation, so this test
// intentionally doesn't go there).
import 'package:driver_rtlsdr_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the initial state with no USB device', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();

    expect(find.text('driver_rtlsdr example'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && (widget.data ?? '').startsWith('Status:'),
      ),
      findsOneWidget,
    );
  });
}
