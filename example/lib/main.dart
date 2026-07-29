import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:ffi/ffi.dart' as pkg_ffi;
import 'package:flutter/material.dart';

/// Minimal example app for driver_rtlsdr — proves that the plugin's public
/// API (USB attach/permission, tuning, streaming, stats) is enough to build
/// a working app on top of it, with no UI coming from the plugin itself.
/// Only WFM/NFM/AM + RF/audio level + stereo pilot lock — no RDS, scan,
/// recording or presets (that's left up to each consumer app; see the
/// `rtl-sdr mobile` app, this package's sibling, for a full
/// implementation).
void main() => runApp(const ExampleApp());

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  late final UsbState _usbState;
  late final UsbChannel _usbChannel;

  @override
  void initState() {
    super.initState();
    _usbState = UsbState();
    _usbChannel = UsbChannel(state: _usbState);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _usbChannel.refreshConnectedDevices(),
    );
  }

  @override
  void dispose() {
    _usbChannel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'driver_rtlsdr example',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('driver_rtlsdr example')),
        body: ListenableBuilder(
          listenable: _usbState,
          builder: (context, _) =>
              _Body(usbState: _usbState, usbChannel: _usbChannel),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.usbState, required this.usbChannel});

  final UsbState usbState;
  final UsbChannel usbChannel;

  @override
  Widget build(BuildContext context) {
    final device = usbState.device;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Status: ${usbState.status.name}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (device != null) ...[
            const SizedBox(height: 8),
            Text(
              '${device.vendorIdHex}:${device.productIdHex} '
              '${device.productName ?? device.deviceName}',
            ),
          ],
          if (usbState.lastError != null) ...[
            const SizedBox(height: 8),
            Text(
              usbState.lastError!,
              style: const TextStyle(color: Colors.red),
            ),
          ],
          const SizedBox(height: 16),
          if (usbState.status == UsbConnectionStatus.attached ||
              usbState.status == UsbConnectionStatus.permissionDenied)
            FilledButton(
              onPressed: usbChannel.requestPermission,
              child: const Text('Grant USB permission'),
            ),
          if (usbState.status == UsbConnectionStatus.permissionRequested)
            const CircularProgressIndicator(),
          if (usbState.status == UsbConnectionStatus.noDevice)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Connect an RTL-SDR dongle via a USB-OTG cable.'),
            ),
          if (usbState.status == UsbConnectionStatus.deviceReady)
            const _TunerDemo(),
        ],
      ),
    );
  }
}

/// Demonstrates the essentials of the `NativeBindings` API directly (with
/// no plugin controller/wrapper — the reference app `rtl-sdr mobile` has a
/// full `RadioController`, but the driver itself does not impose that
/// pattern).
class _TunerDemo extends StatefulWidget {
  const _TunerDemo();

  @override
  State<_TunerDemo> createState() => _TunerDemoState();
}

class _TunerDemoState extends State<_TunerDemo> {
  int _frequencyHz = 100000000;
  bool _isStreaming = false;
  DemodMode _mode = DemodMode.wfm;
  String? _lastError;

  Timer? _statsTimer;
  final ffi.Pointer<ShimStats> _statsPtr = pkg_ffi.calloc<ShimStats>();
  double _rfLevelDbfs = -120;
  double _audioLevelDbfs = -90;
  bool _stereoLocked = false;
  int _iqBytesReceived = 0;

  @override
  void dispose() {
    _statsTimer?.cancel();
    if (_isStreaming) {
      NativeBindings.shimStopStreaming();
    }
    pkg_ffi.calloc.free(_statsPtr);
    super.dispose();
  }

  void _applyFrequency(int hz) {
    final status = NativeBindings.shimSetFrequencyHz(hz);
    setState(() {
      if (status == 0) {
        _frequencyHz = hz;
        _lastError = null;
      } else {
        _lastError = 'Failed to set frequency (status $status)';
      }
    });
  }

  void _setMode(DemodMode mode) {
    NativeBindings.shimSetDemodMode(mode.nativeValue);
    final wasStreaming = _isStreaming;
    if (wasStreaming) _stopStreaming();
    setState(() => _mode = mode);
    // Changing the mode only takes effect on the next shim_start_streaming()
    // call — the native DSP thread reads the mode once, at startup.
    if (wasStreaming) _startStreaming();
  }

  void _startStreaming() {
    final status = NativeBindings.shimStartStreaming();
    if (status != 0) {
      setState(() => _lastError = 'Failed to start streaming (status $status)');
      return;
    }
    setState(() {
      _isStreaming = true;
      _lastError = null;
    });
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _pollStats(),
    );
  }

  void _stopStreaming() {
    NativeBindings.shimStopStreaming();
    _statsTimer?.cancel();
    _statsTimer = null;
    setState(() => _isStreaming = false);
  }

  void _pollStats() {
    if (NativeBindings.shimGetStats(_statsPtr) != 0) return;
    setState(() {
      _rfLevelDbfs = _statsPtr.ref.rfLevelDbfs;
      _audioLevelDbfs = _statsPtr.ref.audioLevelDbfs;
      _stereoLocked = _statsPtr.ref.stereoLocked != 0;
      _iqBytesReceived = _statsPtr.ref.iqBytesReceived;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        Text(
          'Tuned to: ${(_frequencyHz / 1e6).toStringAsFixed(3)} MHz',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Slider(
          value: _frequencyHz.toDouble().clamp(87500000, 108000000),
          min: 87500000,
          max: 108000000,
          onChanged: (v) => _applyFrequency(v.round()),
        ),
        const SizedBox(height: 8),
        SegmentedButton<DemodMode>(
          segments: const [
            ButtonSegment(value: DemodMode.wfm, label: Text('WFM')),
            ButtonSegment(value: DemodMode.nfm, label: Text('NFM')),
            ButtonSegment(value: DemodMode.am, label: Text('AM')),
          ],
          selected: {_mode},
          onSelectionChanged: (selection) => _setMode(selection.first),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _isStreaming ? _stopStreaming : _startStreaming,
          icon: Icon(_isStreaming ? Icons.stop : Icons.play_arrow),
          label: Text(_isStreaming ? 'Stop streaming' : 'Start streaming'),
        ),
        if (_lastError != null) ...[
          const SizedBox(height: 8),
          Text(_lastError!, style: const TextStyle(color: Colors.red)),
        ],
        if (_isStreaming) ...[
          const Divider(height: 32),
          Text(
            'IQ received: ${(_iqBytesReceived / 1e6).toStringAsFixed(2)} MB',
          ),
          Text('RF level: ${_rfLevelDbfs.toStringAsFixed(1)} dBFS'),
          Text('Audio level: ${_audioLevelDbfs.toStringAsFixed(1)} dBFS'),
          if (_mode == DemodMode.wfm)
            Text('Stereo pilot: ${_stereoLocked ? "locked" : "unlocked"}'),
        ],
      ],
    );
  }
}
