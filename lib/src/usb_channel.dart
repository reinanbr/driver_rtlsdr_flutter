import 'dart:async';

import 'package:flutter/services.dart';

import 'usb_state.dart';

/// Bridge to the Kotlin side: requests/reads the RTL-SDR dongle's USB
/// permission state via [MethodChannel] and listens for attach/detach/
/// permission events via [EventChannel]. Kotlin
/// (`DriverRtlsdrPlugin`/`UsbAttachReceiver`) is the only part of the
/// driver that can talk to `android.hardware.usb.UsbManager`.
class UsbChannel {
  UsbChannel({required this.state}) {
    _eventSub = _events.receiveBroadcastStream().listen(
      _onEvent,
      onError: _onEventError,
    );
  }

  static const MethodChannel _methods = MethodChannel('driver_rtlsdr');
  static const EventChannel _events = EventChannel('driver_rtlsdr/events');

  final UsbState state;
  StreamSubscription<Object?>? _eventSub;

  /// Scans already-connected USB devices (useful when opening the app with
  /// the dongle already plugged in, when there's no ATTACHED intent to catch).
  Future<void> refreshConnectedDevices() async {
    try {
      final result = await _methods.invokeMethod<Map<Object?, Object?>>(
        'getConnectedDevice',
      );
      if (result != null) {
        state.deviceAttached(UsbDeviceInfo.fromMap(result));
      }
    } on PlatformException catch (e) {
      state.setError('Failed to query USB devices: ${e.message}');
    }
  }

  Future<void> requestPermission() async {
    try {
      state.permissionRequested();
      await _methods.invokeMethod<void>('requestPermission');
    } on PlatformException catch (e) {
      state.setError('Failed to request permission: ${e.message}');
    }
  }

  void _onEvent(Object? event) {
    if (event is! Map) return;
    final map = event.cast<Object?, Object?>();
    final type = map['type'] as String?;
    switch (type) {
      case 'attached':
        state.deviceAttached(
          UsbDeviceInfo.fromMap(map['device']! as Map<Object?, Object?>),
        );
      case 'detached':
        state.deviceDetached();
      case 'permissionGranted':
        state.permissionGranted(
          UsbDeviceInfo.fromMap(map['device']! as Map<Object?, Object?>),
        );
      case 'permissionDenied':
        state.permissionDenied();
      case 'deviceReady':
        state.deviceReady(
          UsbDeviceInfo.fromMap(map['device']! as Map<Object?, Object?>),
        );
      case 'error':
        state.setError(map['message'] as String? ?? 'Unknown error');
    }
  }

  void _onEventError(Object error) {
    state.setError('Error on the USB event channel: $error');
  }

  void dispose() {
    _eventSub?.cancel();
  }
}
