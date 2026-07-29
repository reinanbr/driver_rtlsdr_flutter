import 'dart:async';

import 'package:flutter/services.dart';

import 'usb_state.dart';

/// Ponte para o lado Kotlin: pede/lê o estado de permissão USB do dongle
/// RTL-SDR via [MethodChannel] e escuta eventos de attach/detach/permissão
/// via [EventChannel]. O Kotlin (`DriverRtlsdrPlugin`/`UsbAttachReceiver`) é
/// a única parte do driver que pode falar com `android.hardware.usb.UsbManager`.
class UsbChannel {
  UsbChannel({required this.state}) {
    _eventSub = _events.receiveBroadcastStream().listen(_onEvent, onError: _onEventError);
  }

  static const MethodChannel _methods = MethodChannel('driver_rtlsdr');
  static const EventChannel _events = EventChannel('driver_rtlsdr/events');

  final UsbState state;
  StreamSubscription<Object?>? _eventSub;

  /// Escaneia os dispositivos USB já conectados (útil ao abrir o app com o
  /// dongle já plugado, quando não há um intent de ATTACHED para pegar).
  Future<void> refreshConnectedDevices() async {
    try {
      final result = await _methods.invokeMethod<Map<Object?, Object?>>('getConnectedDevice');
      if (result != null) {
        state.deviceAttached(UsbDeviceInfo.fromMap(result));
      }
    } on PlatformException catch (e) {
      state.setError('Falha ao consultar dispositivos USB: ${e.message}');
    }
  }

  Future<void> requestPermission() async {
    try {
      state.permissionRequested();
      await _methods.invokeMethod<void>('requestPermission');
    } on PlatformException catch (e) {
      state.setError('Falha ao solicitar permissão: ${e.message}');
    }
  }

  void _onEvent(Object? event) {
    if (event is! Map) return;
    final map = event.cast<Object?, Object?>();
    final type = map['type'] as String?;
    switch (type) {
      case 'attached':
        state.deviceAttached(UsbDeviceInfo.fromMap(map['device']! as Map<Object?, Object?>));
      case 'detached':
        state.deviceDetached();
      case 'permissionGranted':
        state.permissionGranted(UsbDeviceInfo.fromMap(map['device']! as Map<Object?, Object?>));
      case 'permissionDenied':
        state.permissionDenied();
      case 'deviceReady':
        state.deviceReady(UsbDeviceInfo.fromMap(map['device']! as Map<Object?, Object?>));
      case 'error':
        state.setError(map['message'] as String? ?? 'Erro desconhecido');
    }
  }

  void _onEventError(Object error) {
    state.setError('Erro no canal de eventos USB: $error');
  }

  void dispose() {
    _eventSub?.cancel();
  }
}
