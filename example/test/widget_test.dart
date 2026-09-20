// Basic widget test for the example app — runs on the host, without
// Android/a dongle: it only verifies that the UI mounts and shows the
// initial "no device" state (UsbStatusBanner), without attempting any real
// FFI or MethodChannel call.
import 'package:driver_rtlsdr_example/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the initial state with no USB device', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();

    expect(find.text('driver_rtlsdr example'), findsOneWidget);
    expect(find.text('No RTL-SDR dongle detected'), findsOneWidget);
  });
}
