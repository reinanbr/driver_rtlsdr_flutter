import 'dart:async';

import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/device_screen.dart';

/// Canal próprio do app (o pacote `driver_rtlsdr` usa o canal
/// `driver_rtlsdr`, separado deste) — existe só pra iniciar/parar o
/// foreground service Android que mantém o streaming rodando com o app em
/// segundo plano/tela apagada. O pacote deliberadamente não gerencia
/// foreground service: `RadioController` só expõe os hooks
/// onStreamingStarted/onStreamingStopped, plugados aqui.
const MethodChannel _platformChannel = MethodChannel('rtlsdr/usb');

class RtlSdrApp extends StatefulWidget {
  const RtlSdrApp({super.key});

  @override
  State<RtlSdrApp> createState() => _RtlSdrAppState();
}

class _RtlSdrAppState extends State<RtlSdrApp> {
  final RtlSdrDriver _driver = NativeRtlSdrDriver();

  @override
  void dispose() {
    _driver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UsbState()),
        ProxyProvider<UsbState, UsbChannel>(
          update: (_, usbState, previous) =>
              previous ?? UsbChannel(state: usbState),
          dispose: (_, channel) => channel.dispose(),
        ),
        ChangeNotifierProvider(
          create: (_) => RadioController(
            _driver,
            onStreamingStarted: () => unawaited(
              _platformChannel
                  .invokeMethod('startForegroundService')
                  .catchError((_) {}),
            ),
            onStreamingStopped: () => unawaited(
              _platformChannel
                  .invokeMethod('stopForegroundService')
                  .catchError((_) {}),
            ),
          ),
        ),
        ChangeNotifierProvider(
          // `key: 'presets_v1'` preserva os presets já salvos pelos builds
          // anteriores (o pacote usa 'core_rtlsdr_presets_v1' por padrão).
          create: (_) => PresetsController(
            const SharedPreferencesPresetsRepository(key: 'presets_v1'),
          )..load(),
        ),
        ChangeNotifierProvider(create: (_) => RecordingController(_driver)),
        ChangeNotifierProvider(create: (_) => ScanController()),
      ],
      child: MaterialApp(
        title: 'RTL-SDR Mobile',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.teal,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        // Os painéis do pacote (GainPanel, RecordingPanel, ...) renderizam
        // através do RtlSdrTheme — sem um ancestral eles caem no tema
        // escuro fixo, o que destoaria do tema claro do app.
        builder: (context, child) => RtlSdrTheme(
          data: Theme.of(context).brightness == Brightness.dark
              ? RtlSdrThemeData.dark()
              : RtlSdrThemeData.light(),
          child: child ?? const SizedBox.shrink(),
        ),
        home: const DeviceScreen(),
      ),
    );
  }
}
