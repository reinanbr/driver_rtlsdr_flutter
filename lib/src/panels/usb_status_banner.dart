import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter/material.dart';

/// USB permission/attach lifecycle banner — the first thing a host screen
/// shows before the dongle reaches `deviceReady` and the rest of the UI
/// (spectrum, tuning, panels) makes sense to display.
class UsbStatusBanner extends StatelessWidget {
  const UsbStatusBanner({
    super.key,
    required this.usb,
    required this.onRequestPermission,
  });

  final UsbState usb;
  final VoidCallback onRequestPermission;

  @override
  Widget build(BuildContext context) {
    final theme = RtlSdrTheme.of(context);
    return ListenableBuilder(
      listenable: usb,
      builder: (context, _) {
        return RtlSdrPanel(
          title: 'USB',
          icon: _iconFor(usb.status),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    _iconFor(usb.status),
                    color: _colorFor(usb.status, theme),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _labelFor(usb.status),
                      style: TextStyle(color: theme.textPrimary),
                    ),
                  ),
                ],
              ),
              if (usb.device case final device?) ...[
                const SizedBox(height: 8),
                Text(
                  '${device.vendorIdHex}:${device.productIdHex} '
                  '${device.productName ?? device.deviceName}',
                  style: TextStyle(color: theme.textSecondary, fontSize: 12),
                ),
              ],
              if (usb.lastError != null) ...[
                const SizedBox(height: 8),
                Text(usb.lastError!, style: TextStyle(color: theme.meterHot)),
              ],
              if (usb.status == UsbConnectionStatus.attached ||
                  usb.status == UsbConnectionStatus.permissionDenied) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.accent,
                    foregroundColor: theme.background,
                  ),
                  onPressed: onRequestPermission,
                  icon: const Icon(Icons.usb),
                  label: const Text('Grant USB permission'),
                ),
              ],
              if (usb.status == UsbConnectionStatus.permissionRequested) ...[
                const SizedBox(height: 12),
                Center(child: CircularProgressIndicator(color: theme.accent)),
              ],
              if (usb.status == UsbConnectionStatus.noDevice) ...[
                const SizedBox(height: 8),
                Text(
                  'Connect an RTL-SDR dongle via a USB-OTG cable.',
                  style: TextStyle(color: theme.textSecondary),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  IconData _iconFor(UsbConnectionStatus status) => switch (status) {
    UsbConnectionStatus.noDevice => Icons.usb_off,
    UsbConnectionStatus.attached => Icons.usb,
    UsbConnectionStatus.permissionRequested => Icons.usb,
    UsbConnectionStatus.permissionGranted => Icons.check_circle,
    UsbConnectionStatus.permissionDenied => Icons.error,
    UsbConnectionStatus.deviceReady => Icons.check_circle,
  };

  Color _colorFor(UsbConnectionStatus status, RtlSdrThemeData theme) =>
      switch (status) {
        UsbConnectionStatus.noDevice => theme.textSecondary,
        UsbConnectionStatus.attached => theme.cursor,
        UsbConnectionStatus.permissionRequested => theme.accent,
        UsbConnectionStatus.permissionGranted => theme.meterSafe,
        UsbConnectionStatus.permissionDenied => theme.meterHot,
        UsbConnectionStatus.deviceReady => theme.meterSafe,
      };

  String _labelFor(UsbConnectionStatus status) => switch (status) {
    UsbConnectionStatus.noDevice => 'No RTL-SDR dongle detected',
    UsbConnectionStatus.attached => 'Dongle connected — permission needed',
    UsbConnectionStatus.permissionRequested => 'Waiting for permission…',
    UsbConnectionStatus.permissionGranted => 'Permission granted',
    UsbConnectionStatus.permissionDenied => 'Permission denied',
    UsbConnectionStatus.deviceReady => 'Native driver ready',
  };
}
