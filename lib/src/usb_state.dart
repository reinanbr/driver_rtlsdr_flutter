import 'package:flutter/foundation.dart';

/// Connection status with the RTL-SDR dongle, mirroring the lifecycle of
/// Android's USB permission flow (`UsbManager`).
enum UsbConnectionStatus {
  noDevice,
  attached,
  permissionRequested,
  permissionGranted,
  permissionDenied,
  deviceReady,
}

@immutable
class UsbDeviceInfo {
  const UsbDeviceInfo({
    required this.vendorId,
    required this.productId,
    required this.deviceName,
    this.productName,
    this.manufacturerName,
  });

  factory UsbDeviceInfo.fromMap(Map<Object?, Object?> map) {
    return UsbDeviceInfo(
      vendorId: map['vendorId'] as int,
      productId: map['productId'] as int,
      deviceName: map['deviceName'] as String,
      productName: map['productName'] as String?,
      manufacturerName: map['manufacturerName'] as String?,
    );
  }

  final int vendorId;
  final int productId;
  final String deviceName;
  final String? productName;
  final String? manufacturerName;

  String get vendorIdHex => '0x${vendorId.toRadixString(16).padLeft(4, '0')}';
  String get productIdHex => '0x${productId.toRadixString(16).padLeft(4, '0')}';
}

/// Observable state of the USB connection with the RTL-SDR dongle.
///
/// Fed by events coming from the Kotlin side (attach/detach/permission)
/// via [UsbChannel].
class UsbState extends ChangeNotifier {
  UsbConnectionStatus _status = UsbConnectionStatus.noDevice;
  UsbDeviceInfo? _device;
  String? _lastError;

  UsbConnectionStatus get status => _status;
  UsbDeviceInfo? get device => _device;
  String? get lastError => _lastError;

  bool get isPermissionGranted =>
      _status == UsbConnectionStatus.permissionGranted;
  bool get isDeviceReady => _status == UsbConnectionStatus.deviceReady;

  void deviceAttached(UsbDeviceInfo device) {
    _device = device;
    _status = UsbConnectionStatus.attached;
    _lastError = null;
    notifyListeners();
  }

  void deviceDetached() {
    _device = null;
    _status = UsbConnectionStatus.noDevice;
    _lastError = null;
    notifyListeners();
  }

  void permissionRequested() {
    if (_status == UsbConnectionStatus.noDevice) return;
    _status = UsbConnectionStatus.permissionRequested;
    notifyListeners();
  }

  void permissionGranted(UsbDeviceInfo device) {
    _device = device;
    _status = UsbConnectionStatus.permissionGranted;
    _lastError = null;
    notifyListeners();
  }

  void permissionDenied() {
    _status = UsbConnectionStatus.permissionDenied;
    notifyListeners();
  }

  void deviceReady(UsbDeviceInfo device) {
    _device = device;
    _status = UsbConnectionStatus.deviceReady;
    _lastError = null;
    notifyListeners();
  }

  void setError(String message) {
    _lastError = message;
    notifyListeners();
  }
}
