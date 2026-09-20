import 'package:driver_rtlsdr/driver_rtlsdr.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'home_screen.dart';

/// Composition root: wires `UsbState`/`UsbChannel` (USB permission
/// lifecycle) and a [NativeRtlSdrDriver] to the radio-engine controllers —
/// all now exported directly from `driver_rtlsdr` after the 0.3.0 merge of
/// `core_rtlsdr` and `widget_rtlsdr` into this one package.
///
/// Every widget in the package renders through [RtlSdrTheme], so this is
/// also the one place that would switch between [RtlSdrThemeData.dark] and
/// `.light`.
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

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
        Provider<RtlSdrDriver>(
          create: (_) => NativeRtlSdrDriver(),
          dispose: (_, driver) => driver.dispose(),
        ),
        ChangeNotifierProvider(
          create: (context) => RadioController(context.read<RtlSdrDriver>()),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              RecordingController(context.read<RtlSdrDriver>()),
        ),
        ChangeNotifierProvider(create: (_) => ScanController()),
        ChangeNotifierProvider(
          create: (_) =>
              PresetsController(const SharedPreferencesPresetsRepository())
                ..load(),
        ),
      ],
      child: MaterialApp(
        title: 'driver_rtlsdr example',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: const Color(0xFF00E5D1),
          useMaterial3: true,
        ),
        home: RtlSdrTheme(
          data: RtlSdrThemeData.dark(),
          child: const HomeScreen(),
        ),
      ),
    );
  }
}
