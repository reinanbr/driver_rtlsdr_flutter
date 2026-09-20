import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [UsbState] is the Android USB permission/attach lifecycle driver_rtlsdr
/// drives from the Kotlin side (`UsbManager`, see `UsbChannel`) — these
/// tests exercise every state that lifecycle can put a screen in, without
/// needing an actual dongle or Android device (the same reason
/// `core_rtlsdr` ships `FakeRtlSdrDriver`: `UsbState` is plain Dart with no
/// FFI, so it's fully host-testable).
void main() {
  Widget wrap(UsbState usb, {VoidCallback? onRequestPermission}) {
    return MaterialApp(
      home: Scaffold(
        body: UsbStatusBanner(
          usb: usb,
          onRequestPermission: onRequestPermission ?? () {},
        ),
      ),
    );
  }

  testWidgets('noDevice: shows the "connect a dongle" prompt, no button', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(UsbState()));

    expect(find.text('No RTL-SDR dongle detected'), findsOneWidget);
    expect(find.text('Grant USB permission'), findsNothing);
  });

  testWidgets('attached: offers to request permission', (tester) async {
    var requested = false;
    final usb = UsbState()
      ..deviceAttached(
        const UsbDeviceInfo(
          vendorId: 0x0bda,
          productId: 0x2838,
          deviceName: '/dev/bus/usb/001/002',
        ),
      );

    await tester.pumpWidget(
      wrap(usb, onRequestPermission: () => requested = true),
    );

    expect(find.text('Dongle connected — permission needed'), findsOneWidget);
    expect(find.text('Grant USB permission'), findsOneWidget);

    await tester.tap(find.text('Grant USB permission'));
    expect(requested, isTrue);
  });

  testWidgets('permissionRequested: shows a progress indicator', (
    tester,
  ) async {
    final usb = UsbState()
      ..deviceAttached(
        const UsbDeviceInfo(
          vendorId: 0x0bda,
          productId: 0x2838,
          deviceName: 'dev',
        ),
      )
      ..permissionRequested();

    await tester.pumpWidget(wrap(usb));

    expect(find.text('Waiting for permission…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('permissionDenied: offers to retry the permission request', (
    tester,
  ) async {
    final usb = UsbState()
      ..deviceAttached(
        const UsbDeviceInfo(
          vendorId: 0x0bda,
          productId: 0x2838,
          deviceName: 'dev',
        ),
      )
      ..permissionDenied();

    await tester.pumpWidget(wrap(usb));

    expect(find.text('Permission denied'), findsOneWidget);
    expect(find.text('Grant USB permission'), findsOneWidget);
  });

  testWidgets('deviceReady: shows the ready state and device identity', (
    tester,
  ) async {
    final usb = UsbState()
      ..deviceReady(
        const UsbDeviceInfo(
          vendorId: 0x0bda,
          productId: 0x2838,
          deviceName: 'dev',
          productName: 'RTL2838UHIDIR',
        ),
      );

    await tester.pumpWidget(wrap(usb));

    expect(find.text('Native driver ready'), findsOneWidget);
    expect(find.textContaining('0x0bda:0x2838'), findsOneWidget);
    expect(find.textContaining('RTL2838UHIDIR'), findsOneWidget);
    expect(find.text('Grant USB permission'), findsNothing);
  });

  testWidgets('surfaces lastError regardless of status', (tester) async {
    final usb = UsbState()..setError('USB permission request timed out');

    await tester.pumpWidget(wrap(usb));

    expect(find.text('USB permission request timed out'), findsOneWidget);
  });
}
