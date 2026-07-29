import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter_test/flutter_test.dart';

UsbDeviceInfo _device({int vendorId = 0x0bda, int productId = 0x2838}) =>
    UsbDeviceInfo(
      vendorId: vendorId,
      productId: productId,
      deviceName: '/dev/bus/usb/001/002',
      productName: 'RTL2838UHIDIR',
      manufacturerName: 'Realtek',
    );

void main() {
  group('UsbDeviceInfo', () {
    test('fromMap parses required and optional fields', () {
      final info = UsbDeviceInfo.fromMap({
        'vendorId': 3034,
        'productId': 10296,
        'deviceName': '/dev/bus/usb/001/002',
        'productName': 'RTL2838UHIDIR',
        'manufacturerName': 'Realtek',
      });
      expect(info.vendorId, 3034);
      expect(info.productId, 10296);
      expect(info.deviceName, '/dev/bus/usb/001/002');
      expect(info.productName, 'RTL2838UHIDIR');
      expect(info.manufacturerName, 'Realtek');
    });

    test('fromMap tolerates missing optional fields', () {
      final info = UsbDeviceInfo.fromMap({
        'vendorId': 3034,
        'productId': 10296,
        'deviceName': '/dev/bus/usb/001/002',
      });
      expect(info.productName, isNull);
      expect(info.manufacturerName, isNull);
    });

    test('vendorIdHex/productIdHex format as zero-padded lowercase hex', () {
      final info = _device(vendorId: 0x0bda, productId: 0x2838);
      expect(info.vendorIdHex, '0x0bda');
      expect(info.productIdHex, '0x2838');
    });

    test('vendorIdHex pads short values to 4 digits', () {
      final info = _device(vendorId: 0x1, productId: 0xab);
      expect(info.vendorIdHex, '0x0001');
      expect(info.productIdHex, '0x00ab');
    });
  });

  group('UsbState', () {
    test('starts with noDevice and no device/error', () {
      final state = UsbState();
      expect(state.status, UsbConnectionStatus.noDevice);
      expect(state.device, isNull);
      expect(state.lastError, isNull);
      expect(state.isPermissionGranted, isFalse);
      expect(state.isDeviceReady, isFalse);
    });

    test('deviceAttached sets status/device and clears previous error', () {
      final state = UsbState()..setError('boom');
      state.deviceAttached(_device());
      expect(state.status, UsbConnectionStatus.attached);
      expect(state.device, isNotNull);
      expect(state.lastError, isNull);
    });

    test('deviceDetached clears device and resets to noDevice', () {
      final state = UsbState()..deviceAttached(_device());
      state.deviceDetached();
      expect(state.status, UsbConnectionStatus.noDevice);
      expect(state.device, isNull);
    });

    test('permissionRequested is a no-op when there is no device', () {
      final state = UsbState();
      state.permissionRequested();
      expect(state.status, UsbConnectionStatus.noDevice);
    });

    test(
      'full happy-path lifecycle: attached -> requested -> granted -> ready',
      () {
        final state = UsbState();
        final device = _device();

        state.deviceAttached(device);
        expect(state.status, UsbConnectionStatus.attached);

        state.permissionRequested();
        expect(state.status, UsbConnectionStatus.permissionRequested);

        state.permissionGranted(device);
        expect(state.status, UsbConnectionStatus.permissionGranted);
        expect(state.isPermissionGranted, isTrue);

        state.deviceReady(device);
        expect(state.status, UsbConnectionStatus.deviceReady);
        expect(state.isDeviceReady, isTrue);
      },
    );

    test('permissionDenied sets status without touching the device', () {
      final state = UsbState()..deviceAttached(_device());
      state.permissionDenied();
      expect(state.status, UsbConnectionStatus.permissionDenied);
      expect(state.device, isNotNull);
    });

    test('setError records the message without changing status', () {
      final state = UsbState()..deviceAttached(_device());
      state.setError('native driver failed to open the dongle');
      expect(state.lastError, 'native driver failed to open the dongle');
      expect(state.status, UsbConnectionStatus.attached);
    });

    test('notifies listeners on every state transition', () {
      final state = UsbState();
      var notifications = 0;
      state.addListener(() => notifications++);

      state.deviceAttached(_device());
      state.permissionRequested();
      state.permissionGranted(_device());
      state.deviceReady(_device());
      state.deviceDetached();

      expect(notifications, 5);
    });
  });
}
